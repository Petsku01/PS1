# CommonFunctions.psm1
# Shared utility functions for PowerShell scripts
# Version: 1.0
# Date: 2026-01-16

<#
.SYNOPSIS
    Shared module containing common functions used across multiple scripts

.DESCRIPTION
    This module provides standardized functions for:
    - Logging
    - Administrator privilege checking
    - Path validation
    - Error handling
#>

function Write-StandardLog {
    <#
    .SYNOPSIS
        Writes standardized log entries to file and console
    
    .PARAMETER Message
        The log message to write
    
    .PARAMETER Level
        Log level: INFO, WARN, ERROR, DEBUG
    
    .PARAMETER Path
        Path to the log file
    
    .PARAMETER Verbose
        Enable verbose output for DEBUG level
    
    .EXAMPLE
        Write-StandardLog -Message "Processing started" -Level "INFO" -Path "C:\Logs\script.log"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [switch]$VerboseLog
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Ensure directory exists
        $logDir = Split-Path -Path $Path -Parent
        if ($logDir -and -not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }
        
        # Write to file
        Add-Content -Path $Path -Value $logEntry -ErrorAction Stop
        
        # Write to console with color coding
        switch ($Level) {
            'ERROR' { Write-Host $logEntry -ForegroundColor Red }
            'WARN'  { Write-Host $logEntry -ForegroundColor Yellow }
            'DEBUG' { if ($VerboseLog) { Write-Host $logEntry -ForegroundColor Gray } }
            default { Write-Host $logEntry -ForegroundColor Green }
        }
    }
    catch {
        Write-Warning "Failed to write log: $($_.Exception.Message)"
    }
}

function Test-AdministratorPrivilege {
    <#
    .SYNOPSIS
        Checks if the current session has administrator privileges
    
    .PARAMETER Required
        If specified, throws an error when not running as administrator
    
    .PARAMETER ExitOnFail
        If specified, exits the script when not running as administrator
    
    .EXAMPLE
        Test-AdministratorPrivilege -Required
        
    .EXAMPLE
        if (-not (Test-AdministratorPrivilege)) {
            Write-Warning "Limited functionality without admin rights"
        }
    #>
    [CmdletBinding()]
    param(
        [switch]$Required,
        [switch]$ExitOnFail
    )
    
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        if ($Required -or $ExitOnFail) {
            $message = "This script requires administrator privileges. Please run PowerShell as Administrator."
            
            if ($ExitOnFail) {
                Write-Error $message
                exit 1
            }
            else {
                throw $message
            }
        }
    }
    
    return $isAdmin
}

function Get-SafeLogPath {
    <#
    .SYNOPSIS
        Gets a safe log path, creating directory if needed
    
    .PARAMETER BaseDirectory
        Base directory for logs (defaults to user's Documents\Logs)
    
    .PARAMETER FileName
        Log file name (defaults to script name + timestamp)
    
    .EXAMPLE
        $logPath = Get-SafeLogPath -FileName "MyScript.log"
    #>
    [CmdletBinding()]
    param(
        [string]$BaseDirectory,
        [string]$FileName
    )
    
    # Determine base directory
    if (-not $BaseDirectory) {
        if (Test-AdministratorPrivilege) {
            $BaseDirectory = "$env:SystemDrive\Logs"
        }
        else {
            $BaseDirectory = Join-Path $env:USERPROFILE "Documents\Logs"
        }
    }
    
    # Determine filename
    if (-not $FileName) {
        $scriptName = Split-Path -Leaf $PSCommandPath
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $FileName = "${scriptName}_${timestamp}.log"
    }
    
    # Validate filename - whitelist approach (only alphanumeric, dot, dash, underscore)
    $allowedPattern = '^[a-zA-Z0-9._\-]+$'
    if ($FileName -notmatch $allowedPattern) {
        throw "Invalid filename: Must contain only alphanumeric characters, dots, dashes, and underscores. Got: $FileName"
    }
    
    # Also explicitly reject path separators and parent directory
    if ($FileName -match '[/\\]' -or $FileName.StartsWith('..')) {
        throw "Invalid filename: Cannot contain path separators or parent directory references: $FileName"
    }
    
    # Ensure base directory exists
    if (-not (Test-Path -Path $BaseDirectory)) {
        try {
            New-Item -ItemType Directory -Path $BaseDirectory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            # Do not silently fallback - throw error so caller knows
            throw "Failed to create log directory '$BaseDirectory': $_"
        }
    }
    
    # Use .NET GetFullPath for canonical path resolution (handles all edge cases)
    try {
        $baseFullPath = [System.IO.Path]::GetFullPath($BaseDirectory)
        $proposedPath = [System.IO.Path]::Combine($baseFullPath, $FileName)
        $fullPath = [System.IO.Path]::GetFullPath($proposedPath)
        
        # Verify final path is still within base directory (prevent traversal)
        if (-not $fullPath.StartsWith($baseFullPath, [StringComparison]::Ordinal)) {
            throw "Path traversal detected: '$FileName' escapes base directory"
        }
        
        return $fullPath
    }
    catch {
        throw "Path validation failed: $_"
    }
}

function Test-PathWritable {
    <#
    .SYNOPSIS
        Tests if a path is writable
    
    .PARAMETER Path
        Path to test
    
    .EXAMPLE
        if (Test-PathWritable -Path "C:\Logs") { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        $testFile = Join-Path $Path "test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
        "test" | Out-File -FilePath $testFile -ErrorAction Stop
        Remove-Item -Path $testFile -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-FormattedFileSize {
    <#
    .SYNOPSIS
        Formats file size in human-readable format
    
    .PARAMETER Bytes
        Size in bytes
    
    .EXAMPLE
        Get-FormattedFileSize -Bytes 1048576
        # Returns: "1.00 MB"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes
    )
    
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $order = 0
    $size = $Bytes
    
    while ($size -ge 1024 -and $order -lt $sizes.Count - 1) {
        $order++
        $size = $size / 1024
    }
    
    return "{0:N2} {1}" -f $size, $sizes[$order]
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with retry logic
    
    .PARAMETER ScriptBlock
        The script block to execute
    
    .PARAMETER MaxRetries
        Maximum number of retry attempts (default: 3)
    
    .PARAMETER DelaySeconds
        Delay between retries in seconds (default: 5)
    
    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Get-Service -Name "BITS" } -MaxRetries 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [int]$MaxRetries = 3,
        
        [int]$DelaySeconds = 5
    )
    
    $attempt = 0
    $success = $false
    $lastError = $null
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            $result = & $ScriptBlock
            $success = $true
            return $result
        }
        catch {
            $lastError = $_
            
            if ($attempt -lt $MaxRetries) {
                Write-Warning "Attempt $attempt failed: $($_.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    
    if (-not $success) {
        throw "Failed after $MaxRetries attempts. Last error: $($lastError.Exception.Message)"
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Write-StandardLog',
    'Test-AdministratorPrivilege',
    'Get-SafeLogPath',
    'Test-PathWritable',
    'Get-FormattedFileSize',
    'Invoke-WithRetry'
)
