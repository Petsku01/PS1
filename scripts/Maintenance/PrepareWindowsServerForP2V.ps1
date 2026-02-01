<#
.SYNOPSIS
Prepares Windows Server for Physical-to-Virtual migration to Hyper-V.

.DESCRIPTION
Performs comprehensive pre-P2V migration validation including system configuration,
backup creation, and compatibility checks. Generates reports and logs all operations
for troubleshooting. Uses disk2vhd for VHDX conversion.

.PARAMETER BackupPath
Directory for backups and reports. Default: $env:SystemDrive\Backups.

.PARAMETER Disk2VhdPath
Path to disk2vhd.exe utility. Default: $env:SystemDrive\Tools\disk2vhd.exe.

.EXAMPLE
.\PrepareWindowsServerForP2V.ps1 -BackupPath "E:\P2V_Backups" -Disk2VhdPath "C:\Tools\disk2vhd.exe"

.NOTES
Requires Administrator privileges and disk2vhd utility.
Generates detailed system report and migration log.

.LINK
https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/plan
#>

#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Directory for backups and reports")]
    [string]$BackupPath = "$env:SystemDrive\Backups",
    
    [Parameter(HelpMessage = "Path to disk2vhd.exe utility")]
    [string]$Disk2VhdPath = "$env:SystemDrive\Tools\disk2vhd.exe"
)

# Import CommonFunctions for standardized logging
Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction Stop

# Define output paths
$script:backupPath = $BackupPath
$script:reportPath = Join-Path $BackupPath "SystemReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$script:vhdxPath = Join-Path $BackupPath "ServerBackup.vhdx"
$script:disk2vhdPath = $Disk2VhdPath
$script:logPath = Join-Path $BackupPath "P2V_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Check PowerShell version
function Test-PowerShellVersion {
    [CmdletBinding()]
    param()
    
    try {
        if (-not $PSVersionTable -or $PSVersionTable.PSVersion.Major -lt 2) {
            throw "PowerShell version $($PSVersionTable.PSVersion.Major) is too old or not installed. Requires PowerShell 2.0 or higher."
        }
        Write-StandardLog -Message "PowerShell version $($PSVersionTable.PSVersion) is compatible." -Level "INFO" -Path $script:logPath
        return $true
    } catch {
        Write-StandardLog -Message "PowerShell version check failed. Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Check system readiness (disk, memory, Disk2VHD)
function Test-SystemReadiness {
    [CmdletBinding()]
    param()
    
    try {
        # Check system drive accessibility
        $systemDrive = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).SystemDrive
        if (-not (Test-Path $systemDrive)) {
            throw "System drive $systemDrive is not accessible."
        }
        Write-StandardLog -Message "System drive $systemDrive is accessible." -Level "INFO" -Path $script:logPath

        # Check available memory
        $memory = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $freeMemory = $memory.FreePhysicalMemory / 1MB
        if ($freeMemory -lt 1) {
            Write-StandardLog -Message "Low free memory ($freeMemory GB). Recommend closing applications before proceeding." -Level "WARN" -Path $script:logPath
        }

        # Check Disk2VHD existence and basic version
        if (-not (Test-Path $script:disk2vhdPath)) {
            throw "Disk2VHD not found at $($script:disk2vhdPath). Download from Sysinternals."
        }
        $disk2vhdVersion = & $script:disk2vhdPath /? 2>&1 | Select-String "Disk2vhd v"
        Write-StandardLog -Message "Disk2VHD found: $disk2vhdVersion" -Level "INFO" -Path $script:logPath

        # Check disk health
        Write-StandardLog -Message "Checking disk health for $systemDrive..." -Level "INFO" -Path $script:logPath
        $chkdskOutput = chkdsk $systemDrive /f | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Disk health check failed for $systemDrive. Run 'chkdsk $systemDrive /f /r' manually. Output: $chkdskOutput"
        }
        Write-StandardLog -Message "Disk health check passed for $systemDrive." -Level "INFO" -Path $script:logPath
        return $true
    } catch {
        Write-StandardLog -Message "System readiness check failed. Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Create backup directory
function Initialize-BackupDirectory {
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Test-Path $script:backupPath)) {
            New-Item -ItemType Directory -Path $script:backupPath -ErrorAction Stop | Out-Null
            Write-StandardLog -Message "Created backup directory at $($script:backupPath)" -Level "INFO" -Path $script:logPath
        }
        return $true
    } catch {
        Write-StandardLog -Message "Failed to create backup directory at $($script:backupPath). Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Function to collect system information
function Get-SystemInfo {
    [CmdletBinding()]
    param()
    
    try {
        Write-StandardLog -Message "Collecting system information..." -Level "INFO" -Path $script:logPath
        Write-Output "=== System Information ===" | Out-File -FilePath $script:reportPath -ErrorAction Stop
        Write-Output "Hostname: $(hostname)" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "`n--- Hardware ---" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Get-CimInstance Win32_ComputerSystem -ErrorAction Stop | Select-Object Manufacturer, Model, TotalPhysicalMemory | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "`n--- CPU ---" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object Name, NumberOfCores, MaxClockSpeed | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "`n--- Disks ---" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Get-Disk -ErrorAction Stop | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "`n--- Network ---" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        try {
            Get-NetAdapter -ErrorAction Stop | Select-Object Name, InterfaceDescription, MacAddress, Status | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        } catch {
            Write-StandardLog -Message "Get-NetAdapter failed, likely due to older OS. Using netsh fallback." -Level "WARN" -Path $script:logPath
            netsh interface show interface | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        }
        Write-Output "`n--- Services ---" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Get-Service -ErrorAction Stop | Where-Object {$_.Status -eq 'Running'} | Select-Object Name, DisplayName, Status | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-StandardLog -Message "System information saved to $($script:reportPath)" -Level "INFO" -Path $script:logPath
        return $true
    } catch {
        Write-StandardLog -Message "Failed to collect system information. Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Function to perform system backup using Windows Server Backup
function Invoke-SystemBackup {
    [CmdletBinding()]
    param()
    
    try {
        if (Get-Module -ListAvailable -Name WindowsServerBackup -ErrorAction Stop) {
            Write-StandardLog -Message "Performing system backup to $($script:backupPath)..." -Level "INFO" -Path $script:logPath
            $backupResult = wbadmin start backup -backupTarget:$script:backupPath -include:C: -allCritical -quiet 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-StandardLog -Message "Backup completed successfully." -Level "INFO" -Path $script:logPath
            } else {
                throw "Backup failed with exit code $LASTEXITCODE. Details: $backupResult"
            }
        } else {
            Write-StandardLog -Message "Windows Server Backup feature not installed. Skipping backup." -Level "WARN" -Path $script:logPath
        }
        return $true
    } catch {
        Write-StandardLog -Message "Backup failed. Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Function to create VHDX using Disk2VHD with retry logic
function New-VHDXFromDisk {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    try {
        if (Test-Path $script:disk2vhdPath -ErrorAction Stop) {
            # Check system activity
            $cpuUsage = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            if ($cpuUsage -gt 80) {
                Write-StandardLog -Message "High CPU usage ($cpuUsage%). Prompting to stop non-essential services." -Level "WARN" -Path $script:logPath
                $response = Read-Host "Stop non-essential services to reduce file locks? (y/n)"
                if ($response -eq 'y') {
                    Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Name -notlike 'win*' -and $_.Name -notlike 'net*' } | Stop-Service -Force -ErrorAction SilentlyContinue
                    Write-StandardLog -Message "Stopped non-essential services." -Level "INFO" -Path $script:logPath
                }
            }
            # Check disk space
            $systemDrive = (Get-CimInstance Win32_OperatingSystem).SystemDrive
            $freeSpace = (Get-Volume -DriveLetter ($script:backupPath[0]) -ErrorAction Stop).SizeRemaining
            $usedSpace = (Get-Volume -DriveLetter ($systemDrive[0])).Size - (Get-Volume -DriveLetter ($systemDrive[0])).SizeRemaining
            if ($freeSpace -lt $usedSpace) {
                throw "Insufficient disk space on $($script:backupPath). Required: $usedSpace bytes, Available: $freeSpace bytes"
            }
            # Get all drives for VHDX inclusion
            $drives = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter
            $driveList = ($drives | ForEach-Object { "$($_):" }) -join " "
            Write-StandardLog -Message "Creating VHDX for drives: $driveList" -Level "INFO" -Path $script:logPath
            # Retry logic for Disk2VHD
            $maxRetries = 3
            $retryCount = 0
            $vhdxSuccess = $false
            while (-not $vhdxSuccess -and $retryCount -lt $maxRetries) {
                try {
                    $process = Start-Process -FilePath $script:disk2vhdPath -ArgumentList "$driveList $($script:vhdxPath) -accepteula" -Wait -PassThru -ErrorAction Stop
                    if ($process.ExitCode -eq 0) {
                        $vhdxSuccess = $true
                    } else {
                        throw "Disk2VHD failed with exit code $($process.ExitCode)"
                    }
                } catch {
                    $retryCount++
                    Write-StandardLog -Message "Disk2VHD attempt $retryCount failed. Error: $($_.Exception.Message)" -Level "WARN" -Path $script:logPath
                    if ($retryCount -lt $maxRetries) {
                        Write-StandardLog -Message "Retrying in 30 seconds..." -Level "INFO" -Path $script:logPath
                        Start-Sleep -Seconds 30
                    } else {
                        throw "Disk2VHD failed after $maxRetries attempts."
                    }
                }
            }
            # Verify VHDX file
            if (Test-Path $script:vhdxPath) {
                $vhdxSize = (Get-Item $script:vhdxPath -ErrorAction Stop).Length
                if ($vhdxSize -lt 1MB) {
                    throw "VHDX file at $($script:vhdxPath) is too small ($vhdxSize bytes), likely corrupted."
                }
                # Basic checksum
                $hash = Get-FileHash $script:vhdxPath -Algorithm SHA256 -ErrorAction Stop
                Write-StandardLog -Message "VHDX created at $($script:vhdxPath) (Size: $vhdxSize bytes, SHA256: $($hash.Hash))" -Level "INFO" -Path $script:logPath
            } else {
                throw "VHDX file not found at $($script:vhdxPath) after creation."
            }
        } else {
            throw "Disk2VHD not found at $($script:disk2vhdPath). Download from Sysinternals."
        }
        return $true
    } catch {
        Write-StandardLog -Message "Failed to create VHDX. Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Function to provide post-migration steps
function Write-PostMigrationSteps {
    [CmdletBinding()]
    param()
    
    try {
        Write-Output "`n=== Post-Migration Steps ===" | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "1. Copy $($script:vhdxPath) to your Hyper-V host." | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "2. In Hyper-V Manager, create a new VM and attach the VHDX file." | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "3. Configure VM settings (CPU, RAM, Network) to match original server specs (see above)." | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "4. Install Hyper-V Integration Services in the VM." | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "5. Boot the VM and verify network settings (IP, DNS, Gateway)." | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-Output "6. Test all applications and services." | Out-File -FilePath $script:reportPath -Append -ErrorAction Stop
        Write-StandardLog -Message "Post-migration steps added to $($script:reportPath)" -Level "INFO" -Path $script:logPath
        return $true
    } catch {
        Write-StandardLog -Message "Failed to write post-migration steps to $($script:reportPath). Error: $($_.Exception.Message)" -Level "ERROR" -Path $script:logPath
        return $false
    }
}

# Main execution
Write-StandardLog -Message "Starting P2V preparation for Windows Server at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')..." -Level "INFO" -Path $script:logPath

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-StandardLog -Message "Script must be run as Administrator. Exiting." -Level "ERROR" -Path $script:logPath
    exit 1
}

# Execute steps with error handling
$success = $true

if ($success) { $success = Initialize-BackupDirectory }
if ($success) { $success = Test-PowerShellVersion }
if ($success) { $success = Test-SystemReadiness }
if ($success) { $success = Get-SystemInfo }
if ($success) { $success = Invoke-SystemBackup }
if ($success) { $success = New-VHDXFromDisk }
if ($success) { $success = Write-PostMigrationSteps }

if ($success) {
    Write-StandardLog -Message "P2V preparation completed successfully. Review $($script:reportPath) and $($script:logPath) for details." -Level "INFO" -Path $script:logPath
} else {
    Write-StandardLog -Message "P2V preparation failed. Check $($script:logPath) for errors." -Level "ERROR" -Path $script:logPath
    exit 1
}
