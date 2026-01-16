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

# PrepareWindowsServerForP2V.ps1
# Virtualization
# Script to prepare a Windows Server for P2V migration to Hyper-V with enhanced error handling
# Run as Administrator on the source Windows Server

#Requires -RunAsAdministrator
#Requires -Version 5.1

# Import CommonFunctions for standardized logging
Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction Stop

param(
    [string]$BackupPath = "$env:SystemDrive\Backups",
    [string]$Disk2VhdPath = "$env:SystemDrive\Tools\disk2vhd.exe"
)

# Define output paths
$backupPath = $BackupPath
$reportPath = Join-Path $backupPath "SystemReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$vhdxPath = Join-Path $backupPath "ServerBackup.vhdx"
$disk2vhdPath = $Disk2VhdPath
$logPath = Join-Path $backupPath "P2V_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Check PowerShell version
function Test-PowerShellVersion {
    try {
        if (-not $PSVersionTable -or $PSVersionTable.PSVersion.Major -lt 2) {
            throw "PowerShell version $($PSVersionTable.PSVersion.Major) is too old or not installed. Requires PowerShell 2.0 or higher."
        }
        Write-StandardLog -Message "PowerShell version $($PSVersionTable.PSVersion) is compatible." -Level "INFO" -Path $logPath
        return $true
    } catch {
        Write-StandardLog -Message "PowerShell version check failed. Error: $($_.Exception.Message)" -Level "ERROR" -Path $logPath
        return $false
    }
}

# Check system readiness (disk, memory, Disk2VHD)
function Test-SystemReadiness {
    try {
        # Check system drive accessibility
        $systemDrive = (Get-WmiObject Win32_OperatingSystem -ErrorAction Stop).SystemDrive
        if (-not (Test-Path $systemDrive)) {
            throw "System drive $systemDrive is not accessible."
        }
        Write-Log "System drive $systemDrive is accessible."

        # Check available memory
        $memory = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
        $freeMemory = $memory.FreePhysicalMemory / 1MB
        if ($freeMemory -lt 1) {
            Write-Log "Low free memory ($freeMemory GB). Recommend closing applications before proceeding." "WARNING"
        }

        # Check Disk2VHD existence and basic version
        if (-not (Test-Path $disk2vhdPath)) {
            throw "Disk2VHD not found at $disk2vhdPath. Download from Sysinternals."
        }
        $disk2vhdVersion = & $disk2vhdPath /? 2>&1 | Select-String "Disk2vhd v"
        Write-Log "Disk2VHD found: $disk2vhdVersion"

        # Check disk health
        Write-Log "Checking disk health for $systemDrive..."
        $chkdsk = chkdsk $systemDrive /f | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Disk health check failed for $systemDrive. Run 'chkdsk $systemDrive /f /r' manually."
        }
        Write-Log "Disk health check passed for $systemDrive."
        return $true
    } catch {
        Write-Log "System readiness check failed. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Create backup directory
try {
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -ErrorAction Stop | Out-Null
        Write-Log "Created backup directory at $backupPath"
    }
} catch {
    Write-Log "Failed to create backup directory at $backupPath. Error: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Function to collect system information
function Get-SystemInfo {
    try {
        Write-Log "Collecting system information..."
        Write-Output "=== System Information ===" | Out-File -FilePath $reportPath -ErrorAction Stop
        Write-Output "Hostname: $(hostname)" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "`n--- Hardware ---" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Get-WmiObject Win32_ComputerSystem -ErrorAction Stop | Select-Object Manufacturer, Model, TotalPhysicalMemory | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "`n--- CPU ---" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Get-WmiObject Win32_Processor -ErrorAction Stop | Select-Object Name, NumberOfCores, MaxClockSpeed | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "`n--- Disks ---" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Get-Disk -ErrorAction Stop | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "`n--- Network ---" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        try {
            Get-NetAdapter -ErrorAction Stop | Select-Object Name, InterfaceDescription, MacAddress, Status | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        } catch {
            Write-Log "Get-NetAdapter failed, likely due to older OS. Using netsh fallback." "WARNING"
            netsh interface show interface | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        }
        Write-Output "`n--- Services ---" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Get-Service -ErrorAction Stop | Where-Object {$_.Status -eq 'Running'} | Select-Object Name, DisplayName, Status | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Log "System information saved to $reportPath"
        return $true
    } catch {
        Write-Log "Failed to collect system information. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to perform system backup using Windows Server Backup
function Perform-SystemBackup {
    try {
        if (Get-Module -ListAvailable -Name WindowsServerBackup -ErrorAction Stop) {
            Write-Log "Performing system backup to $backupPath..."
            $backupResult = wbadmin start backup -backupTarget:$backupPath -include:C: -allCritical -quiet 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Backup completed successfully."
            } else {
                throw "Backup failed with exit code $LASTEXITCODE. Details: $backupResult"
            }
        } else {
            Write-Log "Windows Server Backup feature not installed. Skipping backup." "WARNING"
        }
        return $true
    } catch {
        Write-Log "Backup failed. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to create VHDX using Disk2VHD with retry logic
function Create-VHDX {
    try {
        if (Test-Path $disk2vhdPath -ErrorAction Stop) {
            # Check system activity
            $cpuUsage = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            if ($cpuUsage -gt 80) {
                Write-Log "High CPU usage ($cpuUsage%). Prompting to stop non-essential services." "WARNING"
                $response = Read-Host "Stop non-essential services to reduce file locks? (y/n)"
                if ($response -eq 'y') {
                    Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Name -notlike 'win*' -and $_.Name -notlike 'net*' } | Stop-Service -Force -ErrorAction SilentlyContinue
                    Write-Log "Stopped non-essential services."
                }
            }
            # Check disk space
            $systemDrive = (Get-WmiObject Win32_OperatingSystem).SystemDrive
            $freeSpace = (Get-Volume -DriveLetter ($backupPath[0]) -ErrorAction Stop).SizeRemaining
            $usedSpace = (Get-Volume -DriveLetter ($systemDrive[0])).Size - (Get-Volume -DriveLetter ($systemDrive[0])).SizeRemaining
            if ($freeSpace -lt $usedSpace) {
                throw "Insufficient disk space on $backupPath. Required: $usedSpace bytes, Available: $freeSpace bytes"
            }
            # Get all drives for VHDX inclusion
            $drives = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter
            $driveList = ($drives | ForEach-Object { "$($_):" }) -join " "
            Write-Log "Creating VHDX for drives: $driveList"
            # Retry logic for Disk2VHD
            $maxRetries = 3
            $retryCount = 0
            $success = $false
            while (-not $success -and $retryCount -lt $maxRetries) {
                try {
                    $process = Start-Process -FilePath $disk2vhdPath -ArgumentList "$driveList $vhdxPath -accepteula" -Wait -PassThru -ErrorAction Stop
                    if ($process.ExitCode -eq 0) {
                        $success = $true
                    } else {
                        throw "Disk2VHD failed with exit code $($process.ExitCode)"
                    }
                } catch {
                    $retryCount++
                    Write-Log "Disk2VHD attempt $retryCount failed. Error: $($_.Exception.Message)" "WARNING"
                    if ($retryCount -lt $maxRetries) {
                        Write-Log "Retrying in 30 seconds..."
                        Start-Sleep -Seconds 30
                    } else {
                        throw "Disk2VHD failed after $maxRetries attempts."
                    }
                }
            }
            # Verify VHDX file
            if (Test-Path $vhdxPath) {
                $vhdxSize = (Get-Item $vhdxPath -ErrorAction Stop).Length
                if ($vhdxSize -lt 1MB) {
                    throw "VHDX file at $vhdxPath is too small ($vhdxSize bytes), likely corrupted."
                }
                # Basic checksum
                $hash = Get-FileHash $vhdxPath -Algorithm MD5 -ErrorAction Stop
                Write-Log "VHDX created at $vhdxPath (Size: $vhdxSize bytes, MD5: $($hash.Hash))"
            } else {
                throw "VHDX file not found at $vhdxPath after creation."
            }
        } else {
            throw "Disk2VHD not found at $disk2vhdPath. Download from Sysinternals."
        }
        return $true
    } catch {
        Write-Log "Failed to create VHDX. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to provide post-migration steps
function Post-MigrationSteps {
    try {
        Write-Output "`n=== Post-Migration Steps ===" | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "1. Copy $vhdxPath to your Hyper-V host." | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "2. In Hyper-V Manager, create a new VM and attach the VHDX file." | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "3. Configure VM settings (CPU, RAM, Network) to match original server specs (see above)." | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "4. Install Hyper-V Integration Services in the VM." | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "5. Boot the VM and verify network settings (IP, DNS, Gateway)." | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Output "6. Test all applications and services." | Out-File -FilePath $reportPath -Append -ErrorAction Stop
        Write-Log "Post-migration steps added to $reportPath"
        return $true
    } catch {
        Write-Log "Failed to write post-migration steps to $reportPath. Error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "Starting P2V preparation for Windows Server at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')..."

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator. Exiting." "ERROR"
    exit 1
}

# Execute steps with error handling
$success = $true

if ($success) { $success = Test-PowerShellVersion }
if ($success) { $success = Test-SystemReadiness }
if ($success) { $success = Get-SystemInfo }
if ($success) { $success = Perform-SystemBackup }
if ($success) { $success = Create-VHDX }
if ($success) { $success = Post-MigrationSteps }

if ($success) {
    Write-Log "P2V preparation completed successfully. Review $reportPath and $logPath for details."
} else {
    Write-Log "P2V preparation failed. Check $logPath for errors." "ERROR"
    exit 1
}
