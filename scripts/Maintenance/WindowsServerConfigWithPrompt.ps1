#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
Automated Windows Server configuration with interactive prompts.

.DESCRIPTION
Guides sysadmin through comprehensive server setup including networking, services,
roles, and security settings. Interactive prompts collect configuration preferences.
Optimized for Windows Server 2019/2022.

.PARAMETER LogDirectory
Directory for configuration logs. Default: $env:SystemDrive\Logs.

.EXAMPLE
.\WindowsServerConfigWithPrompt.ps1 -LogDirectory "E:\ServerLogs"

.NOTES
Requires Administrator privileges.
Compatible with PowerShell 5.1 on Server 2019/2022.

.LINK
https://docs.microsoft.com/en-us/windows-server/administration/
#>

param(
    [string]$LogDirectory = "$env:SystemDrive\Logs"
)

# Import CommonFunctions for standardized logging
Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction SilentlyContinue

# WindowsServerConfigWithPrompt.ps1
# Updated in 2025
# PowerShell script to configure a new Windows Server with user prompts
# Run as Administrator
# Compatible with Windows Server 2019/2022, PowerShell 5.1 or later

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "This script requires PowerShell 5.1 or later."
    exit 1
}

# Check OS version for compatibility
$osVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
if ($osVersion -notlike "10.0.17763*" -and $osVersion -notlike "10.0.20348*") {
    Write-Warning "This script is optimized for Windows Server 2019/2022. Some features may not work on this OS version: $osVersion"
}

# Log file setup and permission check
$logFile = Join-Path $LogDirectory "ServerConfig_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
try {
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -ErrorAction Stop
    }
    # Verify write permissions
    $testFile = Join-Path $LogDirectory "test_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
    "Test" | Out-File -FilePath $testFile -ErrorAction Stop
    Remove-Item -Path $testFile -ErrorAction Stop
}
catch {
    Write-Error "Failed to create or write to log directory ($LogDirectory): $_"
    exit 1
}

# Check disk space for logging
try {
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    if ($disk.FreeSpace -lt 10MB) {
        Write-Error "Low disk space on C: ($($disk.FreeSpace / 1MB) MB free). Logging may fail."
        exit 1
    }
}
catch {
    Write-Warning "Unable to check disk space: $_"
}

function Write-Log {
    param($Message)
    # Wrapper that uses CommonFunctions if available
    if (Get-Command Write-StandardLog -ErrorAction SilentlyContinue) {
        Write-StandardLog -Message $Message -Level "INFO" -Path $logFile
    } else {
        # Fallback if CommonFunctions not loaded
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
        try {
            Write-Output $logMessage | Out-File -FilePath $logFile -Append -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
        Write-Host $logMessage
    }
}

# Input validation function
function Get-YesNoInput {
    param($Prompt)
    do {
        $response = (Read-Host $Prompt).ToLower()
    } while ($response -notmatch '^[yn]$')
    return $response
}

Write-Log "Starting Windows Server configuration with user prompts."

# Display Prompt Menu
Clear-Host
Write-Host "=== Windows Server Configuration Script ==="
Write-Host "Please select the configurations to apply (y/n for each):"
$configureTimeZone = Get-YesNoInput "Set time zone to UTC? (y/n)"
$configureNetworking = Get-YesNoInput "Configure DNS servers (Google DNS)? (y/n)"
$enableRDP = Get-YesNoInput "Enable Remote Desktop? (y/n)"
$configureFirewall = Get-YesNoInput "Configure firewall (allow ICMP, HTTP, HTTPS)? (y/n)"
$disableFeatures = Get-YesNoInput "Disable unused features (Telnet, TFTP, IE)? (y/n)"
$configureSecurity = Get-YesNoInput "Apply security settings (auto-updates, disable SMBv1)? (y/n)"
$configurePowerPlan = Get-YesNoInput "Set power plan to High Performance? (y/n)"
$installRoles = Get-YesNoInput "Install common roles (Web Server, DNS)? (y/n)"
$runDiskCleanup = Get-YesNoInput "Run disk cleanup? (y/n)"
Write-Host "========================================"

# 1. Set Time Zone
if ($configureTimeZone -eq 'y') {
    try {
        Write-Log "Setting time zone to UTC."
        Set-TimeZone -Id "UTC" -ErrorAction Stop
        Write-Log "Time zone set successfully."
    }
    catch {
        Write-Log "Error setting time zone: $_"
    }
}

# 2. Configure Networking
if ($configureNetworking -eq 'y') {
    try {
        Write-Log "Configuring network settings."
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        if ($adapters.Count -eq 0) {
            Write-Log "No active network adapters found. Skipping network configuration."
        }
        elseif ($adapters.Count -gt 1) {
            Write-Log "Multiple active adapters found. Using first one."
        }
        else {
            $interfaceIndex = $adapters[0].InterfaceIndex
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses ("8.8.8.8", "8.8.4.4") -ErrorAction Stop
            Write-Log "DNS servers set to 8.8.8.8 and 8.8.4.4."
        }
    }
    catch {
        Write-Log "Error configuring network settings: $_"
    }
}

# 3. Enable Remote Desktop
if ($enableRDP -eq 'y') {
    try {
        Write-Log "Enabling Remote Desktop."
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
        Write-Log "Remote Desktop enabled."
    }
    catch {
        Write-Log "Error enabling Remote Desktop: $_"
    }
}

# 4. Configure Windows Firewall
if ($configureFirewall -eq 'y') {
    try {
        Write-Log "Configuring Windows Firewall rules."
        Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -ErrorAction Stop
        if (-not (Get-NetFirewallRule -DisplayName "Allow HTTP" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName "Allow HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -ErrorAction Stop
        }
        if (-not (Get-NetFirewallRule -DisplayName "Allow HTTPS" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName "Allow HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction Stop
        }
        Write-Log "Firewall rules configured."
    }
    catch {
        Write-Log "Error configuring firewall: $_"
    }
}

# 5. Disable Unused Features
if ($disableFeatures -eq 'y') {
    try {
        Write-Log "Disabling unused Windows features."
        $featuresToDisable = @(
            "TelnetClient",
            "TFTP",
            "Internet-Explorer-Optional-amd64"
        )
        foreach ($feature in $featuresToDisable) {
            if (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue) {
                Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop
                Write-Log "Disabled feature: $feature"
            }
            else {
                Write-Log "Feature $feature not found or already disabled."
            }
        }
    }
    catch {
        Write-Log "Error disabling features: $_"
    }
}

# 6. Configure Security Settings
if ($configureSecurity -eq 'y') {
    try {
        Write-Log "Applying security settings."
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name AUOptions -Value 4 -ErrorAction Stop
        Write-Log "Automatic updates enabled."
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
        Write-Log "SMBv1 disabled."
    }
    catch {
        Write-Log "Error applying security settings: $_"
    }
}

# 7. Set Power Plan to High Performance
if ($configurePowerPlan -eq 'y') {
    try {
        Write-Log "Setting power plan to High Performance."
        powercfg /setactive SCHEME_MIN -ErrorAction Stop
        Write-Log "Power plan set to High Performance."
    }
    catch {
        Write-Log "Error setting power plan: $_"
    }
}

# 8. Install Common Roles
if ($installRoles -eq 'y') {
    try {
        Write-Log "Installing common server roles."
        $roles = @("Web-Server", "DNS")
        Install-WindowsFeature -Name $roles -IncludeManagementTools -ErrorAction Stop
        Write-Log "Installed roles: $roles"
    }
    catch {
        Write-Log "Error installing roles: $_"
    }
}

# 9. Clean Up and Optimize
if ($runDiskCleanup -eq 'y') {
    try {
        Write-Log "Checking for disk cleanup tool availability."
        if (-not (Get-Command cleanmgr -ErrorAction SilentlyContinue)) {
            Write-Log "Disk cleanup tool (cleanmgr) not available. Skipping disk cleanup."
        }
        else {
            Write-Log "Running disk cleanup."
            Start-Process -FilePath cleanmgr -ArgumentList "/sageset:1" -Wait -ErrorAction Stop
            Start-Process -FilePath cleanmgr -ArgumentList "/sagerun:1" -Wait -ErrorAction Stop
            Write-Log "Disk cleanup completed."
        }
    }
    catch {
        Write-Log "Error running disk cleanup: $_"
    }
}

# 10. Check for Pending Reboot and Restart
$rebootPending = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name RebootPending -ErrorAction SilentlyContinue) -or
                 (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name RebootRequired -ErrorAction SilentlyContinue)
if ($rebootPending) {
    Write-Log "Warning: A reboot is pending. Some changes may not take effect until the server is restarted."
}

# Log configuration summary
Write-Log "Summary of applied configurations:"
Write-Log "Time Zone: $(if ($configureTimeZone -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Networking: $(if ($configureNetworking -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Remote Desktop: $(if ($enableRDP -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Firewall: $(if ($configureFirewall -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Disable Features: $(if ($disableFeatures -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Security Settings: $(if ($configureSecurity -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Power Plan: $(if ($configurePowerPlan -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Server Roles: $(if ($installRoles -eq 'y') { 'Configured' } else { 'Skipped' })"
Write-Log "Disk Cleanup: $(if ($runDiskCleanup -eq 'y') { 'Configured' } else { 'Skipped' })"

$restart = Get-YesNoInput "Configuration complete. Do you want to restart the server now? (y/n)"
if ($restart -eq 'y') {
    Write-Log "Restarting server."
    try {
        Restart-Computer -Force -ErrorAction Stop
    }
    catch {
        Write-Log "Error restarting server: $_"
    }
}
else {
    Write-Log "Configuration completed. Restart skipped."
}

Write-Log "Script execution finished."
Write-Host "Configuration complete. Check logs at $logFile for details."
