<#
.SYNOPSIS
    Template for creating robust PowerShell scripts

.DESCRIPTION
    This template demonstrates best practices for PowerShell script development:
    - Proper parameter handling
    - Admin privilege checking
    - Standardized logging
    - Error handling
    - Input validation
    - Help documentation

.PARAMETER LogDirectory
    Directory for log files (default: system drive\Logs if admin, user Documents\Logs otherwise)

.PARAMETER ConfigPath
    Path to configuration file (optional)

.PARAMETER Verbose
    Enable verbose output

.PARAMETER WhatIf
    Show what would happen without making changes

.EXAMPLE
    .\ScriptTemplate.ps1
    Run with default settings

.EXAMPLE
    .\ScriptTemplate.ps1 -LogDirectory "D:\Logs" -Verbose
    Run with custom log directory and verbose output

.EXAMPLE
    .\ScriptTemplate.ps1 -WhatIf
    Preview changes without executing

.NOTES
    Author: Your Name
    Version: 1.0
    Last Modified: 2026-01-16
    
    Requires: PowerShell 5.1 or later
    
.LINK
    https://github.com/Petsku01/PS1
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(HelpMessage = "Directory for log files")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Directory '$_' does not exist"
        }
        $true
    })]
    [string]$LogDirectory,
    
    [Parameter(HelpMessage = "Path to configuration file")]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "Config file '$_' not found"
        }
        $true
    })]
    [string]$ConfigPath,
    
    [Parameter(HelpMessage = "Force operation without confirmation")]
    [switch]$Force
)

#region Initialization

# Import common functions module
$modulePath = Join-Path $PSScriptRoot "..\..\CommonFunctions.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Warning "CommonFunctions module not found. Some features may not work."
}

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize variables
$script:StartTime = Get-Date
$script:ErrorCount = 0
$script:WarningCount = 0

#endregion

#region Setup

# Determine log directory
if (-not $LogDirectory) {
    if (Test-AdministratorPrivilege) {
        $LogDirectory = "$env:SystemDrive\Logs"
    } else {
        $LogDirectory = Join-Path $env:USERPROFILE "Documents\Logs"
    }
}

# Create log directory if needed
if (-not (Test-Path $LogDirectory)) {
    try {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    catch {
        Write-Error "Failed to create log directory '$LogDirectory': $_"
        exit 1
    }
}

# Set up logging
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$script:LogFile = Join-Path $LogDirectory "${scriptName}_${timestamp}.log"

# Log script start
Write-StandardLog -Message "=== Script Started ===" -Level "INFO" -Path $script:LogFile
Write-StandardLog -Message "Script: $PSCommandPath" -Level "INFO" -Path $script:LogFile
Write-StandardLog -Message "User: $env:USERNAME" -Level "INFO" -Path $script:LogFile
Write-StandardLog -Message "Computer: $env:COMPUTERNAME" -Level "INFO" -Path $script:LogFile
Write-StandardLog -Message "PowerShell: $($PSVersionTable.PSVersion)" -Level "INFO" -Path $script:LogFile

#endregion

#region Functions

function Initialize-Configuration {
    <#
    .SYNOPSIS
        Loads configuration from file or uses defaults
    #>
    [CmdletBinding()]
    param()
    
    $config = @{
        # Default configuration
        MaxRetries = 3
        TimeoutSeconds = 30
        EnableDebug = $false
    }
    
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        try {
            Write-StandardLog -Message "Loading configuration from: $ConfigPath" -Level "INFO" -Path $script:LogFile
            $fileConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
            
            # Merge with defaults
            foreach ($key in $fileConfig.Keys) {
                $config[$key] = $fileConfig[$key]
            }
            
            Write-StandardLog -Message "Configuration loaded successfully" -Level "INFO" -Path $script:LogFile
        }
        catch {
            Write-StandardLog -Message "Failed to load configuration: $_" -Level "WARN" -Path $script:LogFile
            Write-StandardLog -Message "Using default configuration" -Level "INFO" -Path $script:LogFile
        }
    }
    
    return $config
}

function Get-SystemInformation {
    <#
    .SYNOPSIS
        Gathers system information
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-StandardLog -Message "Gathering system information..." -Level "INFO" -Path $script:LogFile
        
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        
        $info = [PSCustomObject]@{
            ComputerName = $computer.Name
            Domain = $computer.Domain
            OS = $os.Caption
            OSVersion = $os.Version
            Architecture = $os.OSArchitecture
            TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
            LastBootTime = $os.LastBootUpTime
            Uptime = (Get-Date) - $os.LastBootUpTime
        }
        
        Write-StandardLog -Message "System information gathered successfully" -Level "INFO" -Path $script:LogFile
        return $info
    }
    catch {
        $script:ErrorCount++
        Write-StandardLog -Message "Failed to gather system information: $_" -Level "ERROR" -Path $script:LogFile
        throw
    }
}

function Invoke-MainTask {
    <#
    .SYNOPSIS
        Main processing function
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    try {
        Write-StandardLog -Message "Starting main task..." -Level "INFO" -Path $script:LogFile
        
        # Check if we should proceed (respects -WhatIf and -Confirm, or skips if -Force)
        if ($Force -or $PSCmdlet.ShouldProcess("System", "Perform main task")) {
            
            # Simulate work
            $systemInfo = Get-SystemInformation
            
            Write-StandardLog -Message "Computer: $($systemInfo.ComputerName)" -Level "INFO" -Path $script:LogFile
            Write-StandardLog -Message "OS: $($systemInfo.OS)" -Level "INFO" -Path $script:LogFile
            Write-StandardLog -Message "Uptime: $($systemInfo.Uptime.Days) days" -Level "INFO" -Path $script:LogFile
            
            # Add your main logic here
            
            Write-StandardLog -Message "Main task completed successfully" -Level "INFO" -Path $script:LogFile
            return $true
        }
        else {
            Write-StandardLog -Message "Main task skipped (WhatIf mode)" -Level "INFO" -Path $script:LogFile
            return $false
        }
    }
    catch {
        $script:ErrorCount++
        Write-StandardLog -Message "Main task failed: $_" -Level "ERROR" -Path $script:LogFile
        throw
    }
}

function Write-Summary {
    <#
    .SYNOPSIS
        Writes execution summary
    #>
    [CmdletBinding()]
    param(
        [bool]$Success
    )
    
    $duration = (Get-Date) - $script:StartTime
    
    Write-StandardLog -Message "=== Execution Summary ===" -Level "INFO" -Path $script:LogFile
    Write-StandardLog -Message "Duration: $($duration.ToString('hh\:mm\:ss'))" -Level "INFO" -Path $script:LogFile
    Write-StandardLog -Message "Errors: $script:ErrorCount" -Level "INFO" -Path $script:LogFile
    Write-StandardLog -Message "Warnings: $script:WarningCount" -Level "INFO" -Path $script:LogFile
    Write-StandardLog -Message "Status: $(if ($Success) { 'SUCCESS' } else { 'FAILED' })" -Level "INFO" -Path $script:LogFile
    Write-StandardLog -Message "Log file: $script:LogFile" -Level "INFO" -Path $script:LogFile
}

#endregion

#region Main Execution

try {
    # Load configuration
    $config = Initialize-Configuration
    
    # Check prerequisites
    if (-not (Test-AdministratorPrivilege)) {
        Write-StandardLog -Message "Running without administrator privileges - some features may be limited" -Level "WARN" -Path $script:LogFile
        $script:WarningCount++
    }
    
    # Execute main task
    $success = Invoke-MainTask
    
    # Write summary
    Write-Summary -Success $success
    
    # Exit with appropriate code
    if ($success) {
        Write-Host "`nScript completed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "`nScript completed with warnings. Check log file: $script:LogFile" -ForegroundColor Yellow
        exit 0
    }
}
catch {
    # Handle any uncaught errors
    Write-StandardLog -Message "CRITICAL ERROR: $_" -Level "ERROR" -Path $script:LogFile
    Write-StandardLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR" -Path $script:LogFile
    
    Write-Summary -Success $false
    
    Write-Host "`nScript failed! Check log file: $script:LogFile" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup
    Write-StandardLog -Message "=== Script Ended ===" -Level "INFO" -Path $script:LogFile
}

#endregion
