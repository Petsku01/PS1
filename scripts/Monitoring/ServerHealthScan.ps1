<#
.SYNOPSIS
Comprehensive Windows Server health check and diagnostic reporting.

.DESCRIPTION
Performs detailed system diagnostics including CPU, memory, disk, network, event logs,
services, and security baseline checks. Generates timestamped logs and reports for
Server 2008 through Server 2022.

.PARAMETER LogDirectory
Directory for health scan logs. Default: $env:SystemDrive\Logs.

.EXAMPLE
.\ServerHealthScan.ps1 -LogDirectory "E:\Monitoring\Logs"

.NOTES
Requires Administrator privileges.
Includes service status, event log analysis, and disk diagnostics.

.LINK
https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/systeminfo
#>

# ServerHealthScan.ps1
# Windows Server (2008-2022) health check script
# Run as Administrator

#Requires -RunAsAdministrator
#Requires -Version 5.1

# Import CommonFunctions for standardized logging
Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction Stop

param(
    [string]$LogDirectory = "$env:SystemDrive\Logs"
)

# Initialize paths
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = $LogDirectory
$logFile = Join-Path $logPath "ServerHealthScan_$timestamp.log"

# Create log directory
if (!(Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

Write-StandardLog -Message "Starting Windows Server health scan" -Level "INFO" -Path $logFile

# Get server version
Clear-Host
Write-Host "=== Windows Server Health Scan ===" -ForegroundColor Cyan
Write-Host "Select your Windows Server version:"
Write-Host "1. Windows Server 2008/2008 R2"
Write-Host "2. Windows Server 2012/2012 R2"  
Write-Host "3. Windows Server 2016"
Write-Host "4. Windows Server 2019"
Write-Host "5. Windows Server 2022"

do {
    $choice = Read-Host "Enter number (1-5)"
} while ($choice -notmatch '^[1-5]$')

$serverVersion = switch ($choice) {
    '1' { '2008' }
    '2' { '2012' }
    '3' { '2016' }
    '4' { '2019' }
    '5' { '2022' }
}

Write-Log "Selected Windows Server $serverVersion"

# Detect actual OS
$os = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log "OS: $($os.Caption), Build: $($os.BuildNumber)"
} catch {
    Write-Log "Could not detect OS version" "ERROR"
}

# Initialize issues array
$issues = @()

function Add-Issue {
    param(
        [string]$Category,
        [string]$Description,
        [string]$Recommendation
    )
    
    $script:issues += [PSCustomObject]@{
        Category = $Category
        Description = $Description
        Recommendation = $Recommendation
    }
    
    Write-Log "$Category - $Description" "WARNING"
}

# 1. System Uptime
Write-Log "Checking system uptime"
try {
    if ($os) {
        $bootTime = [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
        $uptime = (Get-Date) - $bootTime
        Write-Log "Uptime: $($uptime.Days) days"
        
        if ($uptime.Days -gt 30) {
            Add-Issue "System" `
                      "Server uptime is $($uptime.Days) days" `
                      "Consider rebooting to apply updates"
        }
    }
} catch {
    Write-Log "Error checking uptime" "ERROR"
}

# 2. Event Logs
Write-Log "Scanning event logs"
$yesterday = (Get-Date).AddDays(-1)

if ($serverVersion -eq "2008") {
    # Server 2008 - use Get-EventLog
    foreach ($logName in @('System', 'Application')) {
        try {
            $errors = @(Get-EventLog -LogName $logName -EntryType Error -After $yesterday -Newest 100 2>$null)
            if ($errors.Count -gt 0) {
                $grouped = $errors | Group-Object EventID | Sort-Object Count -Descending | Select-Object -First 3
                foreach ($group in $grouped) {
                    if ($group.Count -gt 10) {
                        Add-Issue "Event Logs" `
                                  "Event ID $($group.Name) occurred $($group.Count) times in $logName" `
                                  "Review Event Viewer for details"
                    }
                }
            }
        } catch {
            Write-Log "Could not access $logName event log" "WARNING"
        }
    }
} else {
    # Server 2012+ - use Get-WinEvent
    try {
        $errors = @(Get-WinEvent -FilterHashtable @{
            LogName = 'System','Application'
            Level = 2
            StartTime = $yesterday
        } -MaxEvents 200 2>$null)
        
        if ($errors.Count -gt 0) {
            $grouped = $errors | Group-Object Id | Sort-Object Count -Descending | Select-Object -First 3
            foreach ($group in $grouped) {
                if ($group.Count -gt 10) {
                    Add-Issue "Event Logs" `
                              "Event ID $($group.Name) occurred $($group.Count) times" `
                              "Review Event Viewer for details"
                }
            }
        }
    } catch {
        Write-Log "Could not access event logs" "WARNING"
    }
}

# 3. Disk Space
Write-Log "Checking disk space"
try {
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($disk in $disks) {
        if ($disk.Size -and $disk.Size -gt 0) {
            $freePercent = [Math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            Write-Log "Drive $($disk.DeviceID): $freePercent% free"
            
            if ($freePercent -lt 10) {
                Add-Issue "Disk" `
                          "Drive $($disk.DeviceID) has only $freePercent% free space" `
                          "Free up disk space or expand storage"
            }
        }
    }
} catch {
    Write-Log "Error checking disk space" "ERROR"
}

# 4. Services
Write-Log "Checking critical services"
$services = @('Dnscache', 'wuauserv', 'EventLog', 'RpcSs')
foreach ($svcName in $services) {
    try {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -ne 'Running') {
                Add-Issue "Services" `
                          "$($svc.DisplayName) is $($svc.Status)" `
                          "Start the service"
            }
        }
    } catch {
        Write-Log "Error checking service $svcName" "WARNING"
    }
}

# 5. Network
Write-Log "Checking network"
try {
    $adapters = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True")
    if ($adapters.Count -eq 0) {
        Add-Issue "Network" `
                  "No active network adapters" `
                  "Check network configuration"
    }
    
    # Test connectivity
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet 2>$null
    if (!$ping) {
        Add-Issue "Network" `
                  "Cannot reach 8.8.8.8" `
                  "Check internet connectivity"
    }
    
    # Test DNS
    try {
        $null = [System.Net.Dns]::GetHostEntry("google.com")
    } catch {
        Add-Issue "Network" `
                  "DNS resolution failed" `
                  "Check DNS settings"
    }
} catch {
    Write-Log "Error checking network" "ERROR"
}

# 6. Security
Write-Log "Checking security"

# Windows Update
$wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
if ($wu -and $wu.Status -ne 'Running') {
    Add-Issue "Security" `
              "Windows Update service not running" `
              "Start wuauserv service"
}

# Check pending updates (skip for 2008)
if ($serverVersion -ne "2008") {
    $updateSession = $null
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $searcher = $updateSession.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
        
        if ($result.Updates.Count -gt 0) {
            Add-Issue "Security" `
                      "$($result.Updates.Count) updates pending" `
                      "Install Windows Updates"
        }
    } catch {
        Write-Log "Could not check updates" "WARNING"
    } finally {
        if ($updateSession) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($updateSession) | Out-Null
        }
    }
}

# SMBv1 (2012+)
if ($serverVersion -in @('2012','2016','2019','2022')) {
    try {
        $smb = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
        if ($smb -and $smb.EnableSMB1Protocol) {
            Add-Issue "Security" `
                      "SMBv1 is enabled" `
                      "Disable SMBv1 for security"
        }
    } catch {
        Write-Log "Could not check SMBv1" "WARNING"
    }
}

# Firewall
if ($serverVersion -eq "2008") {
    $fw = $null
    try {
        $fw = New-Object -ComObject HNetCfg.FwPolicy2
        $profiles = @{1="Domain"; 2="Private"; 4="Public"}
        foreach ($p in $profiles.Keys) {
            if (!$fw.FirewallEnabled[$p]) {
                Add-Issue "Security" `
                          "Firewall disabled for $($profiles[$p])" `
                          "Enable Windows Firewall"
            }
        }
    } catch {
        Write-Log "Could not check firewall" "WARNING"
    } finally {
        if ($fw) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($fw) | Out-Null
        }
    }
} else {
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $disabled = $fwProfiles | Where-Object {!$_.Enabled}
        if ($disabled) {
            Add-Issue "Security" `
                      "Firewall disabled: $($disabled.Name -join ', ')" `
                      "Enable firewall"
        }
    } catch {
        Write-Log "Could not check firewall" "WARNING"
    }
}

# 7. Performance
Write-Log "Checking performance"
try {
    # CPU
    $cpus = Get-CimInstance Win32_Processor
    $avgLoad = 0
    $cpuCount = 0
    
    foreach ($cpu in $cpus) {
        if ($null -ne $cpu.LoadPercentage) {
            $avgLoad += $cpu.LoadPercentage
            $cpuCount++
        }
    }
    
    if ($cpuCount -gt 0) {
        $avgLoad = [Math]::Round($avgLoad / $cpuCount, 2)
        Write-Log "CPU Load: $avgLoad%"
        
        if ($avgLoad -gt 90) {
            Add-Issue "Performance" `
                      "CPU usage is $avgLoad%" `
                      "Check high CPU processes"
        }
    }
    
    # Memory
    if ($os) {
        $totalMem = $os.TotalVisibleMemorySize
        $freeMem = $os.FreePhysicalMemory
        
        if ($totalMem -and $totalMem -gt 0) {
            $usedPercent = [Math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 2)
            Write-Log "Memory Used: $usedPercent%"
            
            if ($usedPercent -gt 90) {
                Add-Issue "Performance" `
                          "Memory usage is $usedPercent%" `
                          "Add memory or optimize apps"
            }
        }
    }
} catch {
    Write-Log "Error checking performance" "ERROR"
}

# Generate Report
$report = [PSCustomObject]@{
    Timestamp = Get-Date
    ServerVersion = $serverVersion
    OSCaption = if ($os) {$os.Caption} else {"Unknown"}
    IssuesFound = $issues.Count
    Issues = $issues
}

$reportFile = "$logPath\ServerHealthReport_$timestamp.json"
$report | ConvertTo-Json -Depth 3 | Set-Content -Path $reportFile

# Display Summary
Write-Host "`n=== Health Scan Complete ===" -ForegroundColor Green
Write-Host "Server: Windows Server $serverVersion"
Write-Host "Issues Found: $($issues.Count)"

if ($issues.Count -gt 0) {
    Write-Host "`nIssues:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  [$($issue.Category)] $($issue.Description)" -ForegroundColor Yellow
        Write-Host "     $($issue.Recommendation)" -ForegroundColor Cyan
    }
} else {
    Write-Host "No issues found!" -ForegroundColor Green
}

Write-Host "`nLog: $logFile"
Write-Host "Report: $reportFile"

Write-Log "Scan completed"

