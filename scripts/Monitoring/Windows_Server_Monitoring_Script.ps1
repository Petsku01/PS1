<#
.SYNOPSIS
Comprehensive monitoring script for Windows servers with alerting.
    
.DESCRIPTION
Advanced server monitoring for Windows servers that checks:
- System performance (CPU, Memory, Disk)
- Network connectivity and interfaces
- Windows services status
- Event log errors and warnings
- Security events
- Hardware health
- Disk space and health
- Process resource consumption
- Temperature monitoring (if available)
- Windows updates status

Supports email alerting, HTML reports, and centralized logging.

.PARAMETER OutputPath
Directory for reports and logs.

.PARAMETER EmailReport
Send results via email.

.PARAMETER SmtpServer
SMTP server for email notifications.

.PARAMETER AlertThreshold
CPU/Memory usage threshold percentage for alerts.

.EXAMPLE
.\Windows_Server_Monitoring_Script.ps1 -OutputPath "C:\Reports" -EmailReport -SmtpServer "mail.company.com"

.NOTES
Requires Administrator privileges.
Comprehensive health check includes multiple system aspects.

.LINK
https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-process
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [string]$OutputPath = "$env:TEMP\ServerMonitor",
    [switch]$EmailReport,
    [string]$SmtpServer = "",
    [int]$AlertThreshold = 0,
    [switch]$Continuous,
    [int]$Interval = 300
)

function Write-Console {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [object[]]$Object,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline,
        [object]$Separator
    )

    Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
}

# Global configuration
$script:Config = @{
    # Performance thresholds
    CPUThreshold = 80
    MemoryThreshold = 85
    DiskSpaceThreshold = 10  # GB free space
    DiskUsageThreshold = 90  # Percentage
    
    # Network monitoring
    PingTargets = @("8.8.8.8", "1.1.1.1", "google.com")
    NetworkTimeoutMs = 5000
    
    # Service monitoring (add critical services here)
    CriticalServices = @("Spooler", "BITS", "Themes", "AudioSrv", "Browser")
    
    # Event log monitoring
    MaxEventAge = 24  # Hours
    CriticalEventIDs = @(1074, 6005, 6006, 6008, 6009, 6013)
    
    # Email configuration
    SMTPServer = "smtp.company.com"
    SMTPPort = 587
    EmailFrom = "monitoring@company.com"
    EmailTo = @("admin@company.com")
    EmailSubject = "Server Monitor Alert - {0}"
    
    # Report settings
    MaxReportAge = 30  # Days to keep reports
    ReportFormat = "HTML"  # HTML, JSON, or CSV
}

if ($SmtpServer) {
    $script:Config.SMTPServer = $SmtpServer
}

if ($AlertThreshold -gt 0) {
    $script:Config.CPUThreshold = $AlertThreshold
    $script:Config.MemoryThreshold = $AlertThreshold
}

# Initialize logging
$script:LogFile = Join-Path $OutputPath "ServerMonitor_$(Get-Date -Format 'yyyyMMdd').log"
$script:Alerts = @()

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log entries (uses CommonFunctions if available)
    #>
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    try {
        # Use CommonFunctions if available
        if (Get-Command Write-StandardLog -ErrorAction SilentlyContinue) {
            Write-StandardLog -Message $Message -Level $Level -Path $script:LogFile
        } else {
            # Fallback implementation
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logEntry = "[$timestamp] [$Level] $Message"
            
            # Ensure output directory exists
            if (!(Test-Path -Path $OutputPath)) {
                New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            }
            
            # Write to log file
            Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
            
            # Write to console with color coding
            switch ($Level) {
                'ERROR' { Write-Host $logEntry -ForegroundColor Red }
                'WARN'  { Write-Host $logEntry -ForegroundColor Yellow }
                'DEBUG' { if ($Verbose) { Write-Host $logEntry -ForegroundColor Gray } }
                default { Write-Host $logEntry -ForegroundColor Green }
            }
        }
    }
    catch {
        Write-Warning "Failed to write log: $($_.Exception.Message)"
    }
}

function Add-Alert {
    <#
    .SYNOPSIS
        Adds alert to the global alerts collection
    #>
    param(
        [string]$Category,
        [string]$Severity,
        [string]$Message,
        [string]$Details = ""
    )
    
    $alert = [PSCustomObject]@{
        Timestamp = Get-Date
        Category = $Category
        Severity = $Severity
        Message = $Message
        Details = $Details
        ComputerName = $env:COMPUTERNAME
    }
    
    $script:Alerts += $alert
    Write-Log "ALERT [$Severity] $Category - $Message" -Level "WARN"
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Checks if script is running with administrator privileges
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Gathers basic system information
    #>
    try {
        Write-Log "Gathering system information..." -Level "DEBUG"
        
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        
        return [PSCustomObject]@{
            ComputerName = $computer.Name
            Domain = $computer.Domain
            OS = $os.Caption
            OSVersion = $os.Version
            ServicePack = $os.ServicePackMajorVersion
            Architecture = $os.OSArchitecture
            TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
            Manufacturer = $computer.Manufacturer
            Model = $computer.Model
            BIOSVersion = $bios.SMBIOSBIOSVersion
            LastBootTime = $os.LastBootUpTime
            Uptime = (Get-Date) - $os.LastBootUpTime
        }
    }
    catch {
        Write-Log "Failed to gather system information: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

#endregion

#region Performance Monitoring

function Get-CPUUsage {
    <#
    .SYNOPSIS
        Gets current CPU usage percentage
    #>
    try {
        Write-Log "Checking CPU usage..." -Level "DEBUG"
        
        # Get CPU usage over 5 seconds for accuracy
        $cpu1 = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'"
        Start-Sleep -Seconds 5
        $cpu2 = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'"
        
        $cpuPercent = [math]::Round(100 - (($cpu2.PercentIdleTime - $cpu1.PercentIdleTime) / ($cpu2.TimeStamp_Sys100NS - $cpu1.TimeStamp_Sys100NS) * 100), 2)
        
        # Check threshold
        if ($cpuPercent -gt $script:Config.CPUThreshold) {
            Add-Alert -Category "Performance" -Severity "HIGH" -Message "High CPU usage: $cpuPercent%" -Details "Threshold: $($script:Config.CPUThreshold)%"
        }
        
        return [PSCustomObject]@{
            CPUUsagePercent = $cpuPercent
            Threshold = $script:Config.CPUThreshold
            Status = if ($cpuPercent -gt $script:Config.CPUThreshold) { "WARNING" } else { "OK" }
        }
    }
    catch {
        Write-Log "Failed to get CPU usage: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-MemoryUsage {
    <#
    .SYNOPSIS
        Gets current memory usage information
    #>
    try {
        Write-Log "Checking memory usage..." -Level "DEBUG"
        
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $totalMemory = $os.TotalVisibleMemorySize * 1KB
        $freeMemory = $os.FreePhysicalMemory * 1KB
        $usedMemory = $totalMemory - $freeMemory
        $memoryPercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)
        
        # Check threshold
        if ($memoryPercent -gt $script:Config.MemoryThreshold) {
            Add-Alert -Category "Performance" -Severity "HIGH" -Message "High memory usage: $memoryPercent%" -Details "Threshold: $($script:Config.MemoryThreshold)%"
        }
        
        return [PSCustomObject]@{
            TotalMemoryGB = [math]::Round($totalMemory / 1GB, 2)
            UsedMemoryGB = [math]::Round($usedMemory / 1GB, 2)
            FreeMemoryGB = [math]::Round($freeMemory / 1GB, 2)
            MemoryUsagePercent = $memoryPercent
            Threshold = $script:Config.MemoryThreshold
            Status = if ($memoryPercent -gt $script:Config.MemoryThreshold) { "WARNING" } else { "OK" }
        }
    }
    catch {
        Write-Log "Failed to get memory usage: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-DiskUsage {
    <#
    .SYNOPSIS
        Gets disk usage information for all drives
    #>
    try {
        Write-Log "Checking disk usage..." -Level "DEBUG"
        
        $diskInfo = @()
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        
        foreach ($disk in $disks) {
            $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
            $usedSpaceGB = $totalSpaceGB - $freeSpaceGB
            $usagePercent = if ($totalSpaceGB -gt 0) { [math]::Round(($usedSpaceGB / $totalSpaceGB) * 100, 2) } else { 0 }
            
            $status = "OK"
            if ($freeSpaceGB -lt $script:Config.DiskSpaceThreshold -or $usagePercent -gt $script:Config.DiskUsageThreshold) {
                $status = "WARNING"
                Add-Alert -Category "Storage" -Severity "MEDIUM" -Message "Low disk space on $($disk.DeviceID)" -Details "Free: $freeSpaceGB GB ($usagePercent% used)"
            }
            
            $diskInfo += [PSCustomObject]@{
                Drive = $disk.DeviceID
                Label = $disk.VolumeName
                TotalSpaceGB = $totalSpaceGB
                UsedSpaceGB = $usedSpaceGB
                FreeSpaceGB = $freeSpaceGB
                UsagePercent = $usagePercent
                Status = $status
            }
        }
        
        return $diskInfo
    }
    catch {
        Write-Log "Failed to get disk usage: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

#endregion

#region Network Monitoring

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests network connectivity to specified targets
    #>
    try {
        Write-Log "Testing network connectivity..." -Level "DEBUG"
        
        $networkTests = @()
        
        foreach ($target in $script:Config.PingTargets) {
            try {
                $ping = Test-Connection -ComputerName $target -Count 3 -Quiet -TimeoutSeconds ($script:Config.NetworkTimeoutMs / 1000)
                $status = if ($ping) { "OK" } else { "FAILED" }
                
                if (-not $ping) {
                    Add-Alert -Category "Network" -Severity "HIGH" -Message "Network connectivity failed to $target"
                }
                
                $networkTests += [PSCustomObject]@{
                    Target = $target
                    Status = $status
                    Timestamp = Get-Date
                }
            }
            catch {
                Add-Alert -Category "Network" -Severity "HIGH" -Message "Network test error for $target" -Details $_.Exception.Message
                
                $networkTests += [PSCustomObject]@{
                    Target = $target
                    Status = "ERROR"
                    Timestamp = Get-Date
                }
            }
        }
        
        return $networkTests
    }
    catch {
        Write-Log "Failed to test network connectivity: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Get-NetworkAdapters {
    <#
    .SYNOPSIS
        Gets network adapter information
    #>
    try {
        Write-Log "Gathering network adapter information..." -Level "DEBUG"
        
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        $adapterInfo = @()
        
        foreach ($adapter in $adapters) {
            try {
                $config = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
                
                $adapterInfo += [PSCustomObject]@{
                    Name = $adapter.Name
                    Description = $adapter.InterfaceDescription
                    Status = $adapter.Status
                    Speed = $adapter.LinkSpeed
                    IPAddress = if ($config.IPv4Address) { $config.IPv4Address.IPAddress -join ", " } else { "N/A" }
                    Gateway = if ($config.IPv4DefaultGateway) { $config.IPv4DefaultGateway.NextHop -join ", " } else { "N/A" }
                    DNS = if ($config.DNSServer) { $config.DNSServer.ServerAddresses -join ", " } else { "N/A" }
                }
            }
            catch {
                Write-Log "Failed to get configuration for adapter $($adapter.Name): $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        return $adapterInfo
    }
    catch {
        Write-Log "Failed to get network adapters: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

#endregion

#region Service Monitoring

function Get-ServiceStatus {
    <#
    .SYNOPSIS
        Checks status of critical services
    #>
    try {
        Write-Log "Checking service status..." -Level "DEBUG"
        
        $serviceStatus = @()
        
        foreach ($serviceName in $script:Config.CriticalServices) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                
                if ($service) {
                    if ($service.Status -ne "Running") {
                        Add-Alert -Category "Services" -Severity "HIGH" -Message "Critical service not running: $serviceName" -Details "Status: $($service.Status)"
                    }
                    
                    $serviceStatus += [PSCustomObject]@{
                        ServiceName = $service.Name
                        DisplayName = $service.DisplayName
                        Status = $service.Status
                        StartType = $service.StartType
                    }
                } else {
                    Add-Alert -Category "Services" -Severity "MEDIUM" -Message "Critical service not found: $serviceName"
                    
                    $serviceStatus += [PSCustomObject]@{
                        ServiceName = $serviceName
                        DisplayName = "Not Found"
                        Status = "NotFound"
                        StartType = "Unknown"
                    }
                }
            }
            catch {
                Write-Log "Failed to check service $serviceName`: $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        return $serviceStatus
    }
    catch {
        Write-Log "Failed to get service status: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

#endregion

#region Event Log Monitoring

function Get-RecentErrors {
    <#
    .SYNOPSIS
        Gets recent error events from system event logs
    #>
    try {
        Write-Log "Checking recent error events..." -Level "DEBUG"
        
        $cutoffTime = (Get-Date).AddHours(-$script:Config.MaxEventAge)
        $errorEvents = @()
        
        $logNames = @("System", "Application", "Security")
        
        foreach ($logName in $logNames) {
            try {
                $events = Get-WinEvent -LogName $logName -MaxEvents 1000 -ErrorAction SilentlyContinue | 
                          Where-Object { $_.TimeCreated -gt $cutoffTime -and $_.LevelDisplayName -in @("Error", "Critical") }
                
                foreach ($eventItem in $events) {
                    $errorEvents += [PSCustomObject]@{
                        TimeCreated = $eventItem.TimeCreated
                        LogName = $eventItem.LogName
                        Level = $eventItem.LevelDisplayName
                        EventID = $eventItem.Id
                        Source = $eventItem.ProviderName
                        Message = $eventItem.Message.Substring(0, [Math]::Min(200, $eventItem.Message.Length))
                    }
                }
            }
            catch {
                Write-Log "Failed to read $logName log: $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # Alert on critical events
        $criticalEvents = $errorEvents | Where-Object { $_.EventID -in $script:Config.CriticalEventIDs }
        foreach ($criticalEvent in $criticalEvents) {
            Add-Alert -Category "EventLog" -Severity "HIGH" -Message "Critical event detected: ID $($criticalEvent.EventID)" -Details $criticalEvent.Message
        }
        
        return $errorEvents | Sort-Object TimeCreated -Descending | Select-Object -First 50
    }
    catch {
        Write-Log "Failed to get recent errors: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

#endregion

#region Process Monitoring

function Get-TopProcesses {
    <#
    .SYNOPSIS
        Gets top processes by CPU and memory usage
    #>
    try {
        Write-Log "Getting top processes..." -Level "DEBUG"
        
        $processes = Get-Process | Select-Object Name, Id, CPU, WorkingSet64, PagedMemorySize64 | 
                     Where-Object { $_.CPU -gt 0 } |
                     Sort-Object CPU -Descending |
                     Select-Object -First 10
        
        $processInfo = @()
        
        foreach ($proc in $processes) {
            $processInfo += [PSCustomObject]@{
                ProcessName = $proc.Name
                ProcessID = $proc.Id
                CPUTime = [math]::Round($proc.CPU, 2)
                WorkingSetMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
                PagedMemoryMB = [math]::Round($proc.PagedMemorySize64 / 1MB, 2)
            }
        }
        
        return $processInfo
    }
    catch {
        Write-Log "Failed to get top processes: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

#endregion

#region Hardware Monitoring

function Get-HardwareHealth {
    <#
    .SYNOPSIS
        Checks hardware health using WMI (limited without specialized tools)
    #>
    try {
        Write-Log "Checking hardware health..." -Level "DEBUG"
        
        $hardwareInfo = @{
            TemperatureSensors = @()
            Fans = @()
            PowerSupply = @()
        }
        
        # Try to get temperature information (may not be available on all systems)
        try {
            $temps = Get-CimInstance -Namespace "root\wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue
            foreach ($temp in $temps) {
                $celsius = [math]::Round(($temp.CurrentTemperature / 10) - 273.15, 1)
                $hardwareInfo.TemperatureSensors += [PSCustomObject]@{
                    Zone = $temp.InstanceName
                    TemperatureC = $celsius
                    Status = if ($celsius -gt 70) { "HIGH" } elseif ($celsius -gt 60) { "WARM" } else { "OK" }
                }
                
                if ($celsius -gt 80) {
                    Add-Alert -Category "Hardware" -Severity "HIGH" -Message "High temperature detected: $celsiusC" -Details "Zone: $($temp.InstanceName)"
                }
            }
        }
        catch {
            Write-Log "Temperature monitoring not available: $($_.Exception.Message)" -Level "DEBUG"
        }
        
        # Check disk health using SMART (basic check)
        try {
            $diskDrives = Get-CimInstance -ClassName Win32_DiskDrive
            foreach ($drive in $diskDrives) {
                $status = if ($drive.Status -eq "OK") { "OK" } else { "WARNING" }
                if ($status -eq "WARNING") {
                    Add-Alert -Category "Hardware" -Severity "MEDIUM" -Message "Disk drive status warning" -Details "Drive: $($drive.Model), Status: $($drive.Status)"
                }
            }
        }
        catch {
            Write-Log "Failed to check disk drive health: $($_.Exception.Message)" -Level "WARN"
        }
        
        return $hardwareInfo
    }
    catch {
        Write-Log "Failed to get hardware health: $($_.Exception.Message)" -Level "ERROR"
        return @{}
    }
}

#endregion

#region Windows Update Monitoring

function Get-WindowsUpdateStatus {
    <#
    .SYNOPSIS
        Checks Windows Update status
    #>
    try {
        Write-Log "Checking Windows Update status..." -Level "DEBUG"
        
        # Check if Windows Update service is running
        $updateService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        
        $updateInfo = [PSCustomObject]@{
            ServiceStatus = if ($updateService) { $updateService.Status } else { "NotFound" }
            LastInstallDate = "Unknown"
            PendingReboot = $false
            AutoUpdateEnabled = "Unknown"
        }
        
        # Check for pending reboot
        $rebootRequired = $false
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        )
        
        foreach ($key in $rebootKeys) {
            try {
                if (Test-Path $key) {
                    if ($key -like "*Session Manager*") {
                        $pendingFileRenames = Get-ItemProperty -Path $key -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
                        if ($pendingFileRenames) { $rebootRequired = $true }
                    } else {
                        $rebootRequired = $true
                    }
                }
            }
            catch {
                Write-Verbose "Could not check registry key: $($_.Exception.Message)"
            }
        }
        
        $updateInfo.PendingReboot = $rebootRequired
        
        if ($rebootRequired) {
            Add-Alert -Category "Updates" -Severity "MEDIUM" -Message "System reboot required" -Details "Pending updates or system changes require a restart"
        }
        
        return $updateInfo
    }
    catch {
        Write-Log "Failed to get Windows Update status: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

#endregion

#region Reporting Functions

function New-HTMLReport {
    <#
    .SYNOPSIS
        Generates HTML report of monitoring results
    #>
    param(
        [hashtable]$MonitoringData,
        [string]$OutputFile
    )
    
    try {
        Write-Log "Generating HTML report..." -Level "DEBUG"
        
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Monitoring Report - $($MonitoringData.SystemInfo.ComputerName)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .alert-high { background-color: #f8d7da; border-color: #f5c6cb; }
        .alert-medium { background-color: #fff3cd; border-color: #ffeaa7; }
        .alert-low { background-color: #d4edda; border-color: #c3e6cb; }
        .status-ok { color: green; font-weight: bold; }
        .status-warning { color: orange; font-weight: bold; }
        .status-error { color: red; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        .timestamp { font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Server Monitoring Report</h1>
        <p>Server: $($MonitoringData.SystemInfo.ComputerName) | Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>

    <div class="section">
        <h2>System Information</h2>
        <table>
            <tr><td><strong>Computer Name:</strong></td><td>$($MonitoringData.SystemInfo.ComputerName)</td></tr>
            <tr><td><strong>Operating System:</strong></td><td>$($MonitoringData.SystemInfo.OS)</td></tr>
            <tr><td><strong>OS Version:</strong></td><td>$($MonitoringData.SystemInfo.OSVersion)</td></tr>
            <tr><td><strong>Architecture:</strong></td><td>$($MonitoringData.SystemInfo.Architecture)</td></tr>
            <tr><td><strong>Total Memory:</strong></td><td>$($MonitoringData.SystemInfo.TotalMemoryGB) GB</td></tr>
            <tr><td><strong>Last Boot:</strong></td><td>$($MonitoringData.SystemInfo.LastBootTime)</td></tr>
            <tr><td><strong>Uptime:</strong></td><td>$($MonitoringData.SystemInfo.Uptime.Days) days, $($MonitoringData.SystemInfo.Uptime.Hours) hours</td></tr>
        </table>
    </div>

    <div class="section">
        <h2>Performance Summary</h2>
        <table>
            <tr>
                <th>Metric</th>
                <th>Current Value</th>
                <th>Threshold</th>
                <th>Status</th>
            </tr>
            <tr>
                <td>CPU Usage</td>
                <td>$($MonitoringData.Performance.CPU.CPUUsagePercent)%</td>
                <td>$($MonitoringData.Performance.CPU.Threshold)%</td>
                <td class="status-$(($MonitoringData.Performance.CPU.Status -eq 'OK') ? 'ok' : 'warning')">$($MonitoringData.Performance.CPU.Status)</td>
            </tr>
            <tr>
                <td>Memory Usage</td>
                <td>$($MonitoringData.Performance.Memory.MemoryUsagePercent)%</td>
                <td>$($MonitoringData.Performance.Memory.Threshold)%</td>
                <td class="status-$(($MonitoringData.Performance.Memory.Status -eq 'OK') ? 'ok' : 'warning')">$($MonitoringData.Performance.Memory.Status)</td>
            </tr>
        </table>
    </div>

    <div class="section">
        <h2>Disk Usage</h2>
        <table>
            <tr>
                <th>Drive</th>
                <th>Total Space (GB)</th>
                <th>Used Space (GB)</th>
                <th>Free Space (GB)</th>
                <th>Usage %</th>
                <th>Status</th>
            </tr>
"@

        foreach ($disk in $MonitoringData.Performance.Disks) {
            $statusClass = if ($disk.Status -eq 'OK') { 'ok' } else { 'warning' }
            $html += @"
            <tr>
                <td>$($disk.Drive)</td>
                <td>$($disk.TotalSpaceGB)</td>
                <td>$($disk.UsedSpaceGB)</td>
                <td>$($disk.FreeSpaceGB)</td>
                <td>$($disk.UsagePercent)%</td>
                <td class="status-$statusClass">$($disk.Status)</td>
            </tr>
"@
        }

        $html += @"
        </table>
    </div>

    <div class="section">
        <h2>Alerts</h2>
"@

        if ($script:Alerts.Count -gt 0) {
            foreach ($alert in $script:Alerts) {
                $alertClass = switch ($alert.Severity) {
                    'HIGH' { 'alert-high' }
                    'MEDIUM' { 'alert-medium' }
                    default { 'alert-low' }
                }
                
                $html += @"
        <div class="$alertClass section">
            <strong>$($alert.Category) - $($alert.Severity)</strong><br/>
            $($alert.Message)<br/>
            <small class="timestamp">$($alert.Timestamp.ToString("yyyy-MM-dd HH:mm:ss"))</small>
            $(if ($alert.Details) { "<br/><em>Details: $($alert.Details)</em>" })
        </div>
"@
            }
        } else {
            $html += "<p>No alerts generated.</p>"
        }

        $html += @"
    </div>

    <div class="section">
        <h2>Services Status</h2>
        <table>
            <tr>
                <th>Service Name</th>
                <th>Display Name</th>
                <th>Status</th>
                <th>Start Type</th>
            </tr>
"@

        foreach ($service in $MonitoringData.Services) {
            $statusClass = if ($service.Status -eq 'Running') { 'ok' } else { 'error' }
            $html += @"
            <tr>
                <td>$($service.ServiceName)</td>
                <td>$($service.DisplayName)</td>
                <td class="status-$statusClass">$($service.Status)</td>
                <td>$($service.StartType)</td>
            </tr>
"@
        }

        $html += @"
        </table>
    </div>

    <div class="section">
        <h2>Network Connectivity</h2>
        <table>
            <tr>
                <th>Target</th>
                <th>Status</th>
                <th>Test Time</th>
            </tr>
"@

        foreach ($test in $MonitoringData.Network.ConnectivityTests) {
            $statusClass = if ($test.Status -eq 'OK') { 'ok' } else { 'error' }
            $html += @"
            <tr>
                <td>$($test.Target)</td>
                <td class="status-$statusClass">$($test.Status)</td>
                <td>$($test.Timestamp.ToString("HH:mm:ss"))</td>
            </tr>
"@
        }

        $html += @"
        </table>
    </div>

    <div class="section">
        <h2>Top Processes</h2>
        <table>
            <tr>
                <th>Process Name</th>
                <th>Process ID</th>
                <th>CPU Time</th>
                <th>Working Set (MB)</th>
                <th>Paged Memory (MB)</th>
            </tr>
"@

        foreach ($process in $MonitoringData.TopProcesses) {
            $html += @"
            <tr>
                <td>$($process.ProcessName)</td>
                <td>$($process.ProcessID)</td>
                <td>$($process.CPUTime)</td>
                <td>$($process.WorkingSetMB)</td>
                <td>$($process.PagedMemoryMB)</td>
            </tr>
"@
        }

        $html += @"
        </table>
    </div>

    <div class="section">
        <h2>Recent Error Events</h2>
        <table>
            <tr>
                <th>Time</th>
                <th>Log</th>
                <th>Level</th>
                <th>Event ID</th>
                <th>Source</th>
                <th>Message</th>
            </tr>
"@

        foreach ($eventItem in ($MonitoringData.RecentErrors | Select-Object -First 20)) {
            $html += @"
            <tr>
                <td>$($eventItem.TimeCreated.ToString("MM-dd HH:mm"))</td>
                <td>$($eventItem.LogName)</td>
                <td>$($eventItem.Level)</td>
                <td>$($eventItem.EventID)</td>
                <td>$($eventItem.Source)</td>
                <td>$($eventItem.Message)</td>
            </tr>
"@
        }

        $html += @"
        </table>
    </div>

    <div class="timestamp">
        Report generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") by Server Monitor Script v1.0
    </div>

</body>
</html>
"@

        # Write HTML report to file
        $html | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
        Write-Log "HTML report saved to: $OutputFile"
        
        return $true
    }
    catch {
        Write-Log "Failed to generate HTML report: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Send-EmailAlert {
    <#
    .SYNOPSIS
        Sends email alert with monitoring results
    #>
    param(
        [hashtable]$MonitoringData,
        [string]$ReportPath
    )
    
    try {
        Write-Log "Sending email alert..." -Level "DEBUG"
        
        # Check if we have any high-priority alerts
        $criticalAlerts = $script:Alerts | Where-Object { $_.Severity -eq "HIGH" }
        
        if ($criticalAlerts.Count -eq 0 -and !$Continuous) {
            Write-Log "No critical alerts to email." -Level "DEBUG"
            return $true
        }
        
        $subject = $script:Config.EmailSubject -f $MonitoringData.SystemInfo.ComputerName
        
        # Create email body
        $body = @"
Server Monitoring Alert - $($MonitoringData.SystemInfo.ComputerName)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

SUMMARY:
- Total Alerts: $($script:Alerts.Count)
- Critical Alerts: $($criticalAlerts.Count)
- CPU Usage: $($MonitoringData.Performance.CPU.CPUUsagePercent)%
- Memory Usage: $($MonitoringData.Performance.Memory.MemoryUsagePercent)%
- System Uptime: $($MonitoringData.SystemInfo.Uptime.Days) days, $($MonitoringData.SystemInfo.Uptime.Hours) hours

CRITICAL ALERTS:
"@

        foreach ($alert in $criticalAlerts) {
            $body += "`n- [$($alert.Category)] $($alert.Message)"
            if ($alert.Details) {
                $body += " - $($alert.Details)"
            }
        }
        
        $body += "`n`nFull report attached."
        
        # Send email (requires proper SMTP configuration)
        $emailParams = @{
            To = $script:Config.EmailTo
            From = $script:Config.EmailFrom
            Subject = $subject
            Body = $body
            SmtpServer = $script:Config.SMTPServer
            Port = $script:Config.SMTPPort
            Attachments = $ReportPath
        }
        
        # Note: This is a basic example. In production, you'd want to handle authentication
        if (-not $emailParams.SmtpServer -or -not $emailParams.To) {
            Write-Log "SMTP settings incomplete. Email alert skipped." -Level "WARN"
            return $false
        }

        if (-not (Get-Command Send-MailMessage -ErrorAction SilentlyContinue)) {
            Write-Log "Send-MailMessage cmdlet not available. Email alert skipped." -Level "WARN"
            return $false
        }

        Send-MailMessage @emailParams -ErrorAction Stop
        Write-Log "Email alert sent to: $($script:Config.EmailTo -join ', ')" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to send email alert: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-OldReports {
    <#
    .SYNOPSIS
        Cleans up old report files
    #>
    try {
        Write-Log "Cleaning up old reports..." -Level "DEBUG"
        
        $cutoffDate = (Get-Date).AddDays(-$script:Config.MaxReportAge)
        $reportFiles = Get-ChildItem -Path $OutputPath -Filter "*.html" | Where-Object { $_.CreationTime -lt $cutoffDate }
        
        foreach ($file in $reportFiles) {
            Remove-Item -Path $file.FullName -Force
            Write-Log "Deleted old report: $($file.Name)" -Level "DEBUG"
        }
        
        # Also cleanup old log files
        $logFiles = Get-ChildItem -Path $OutputPath -Filter "*.log" | Where-Object { $_.CreationTime -lt $cutoffDate }
        
        foreach ($file in $logFiles) {
            Remove-Item -Path $file.FullName -Force
            Write-Log "Deleted old log: $($file.Name)" -Level "DEBUG"
        }
    }
    catch {
        Write-Log "Failed to cleanup old reports: $($_.Exception.Message)" -Level "WARN"
    }
}

#endregion

#region Main Monitoring Function

function Start-ServerMonitoring {
    <#
    .SYNOPSIS
        Main monitoring function that orchestrates all checks
    #>
    try {
        Write-Log "=== Starting Server Monitoring ===" -Level "INFO"
        
        # Clear previous alerts
        $script:Alerts = @()
        
        # Gather all monitoring data
        $monitoringData = @{
            SystemInfo = Get-SystemInfo
            Performance = @{
                CPU = Get-CPUUsage
                Memory = Get-MemoryUsage
                Disks = Get-DiskUsage
            }
            Network = @{
                ConnectivityTests = Test-NetworkConnectivity
                Adapters = Get-NetworkAdapters
            }
            Services = Get-ServiceStatus
            RecentErrors = Get-RecentErrors
            TopProcesses = Get-TopProcesses
            Hardware = Get-HardwareHealth
            WindowsUpdate = Get-WindowsUpdateStatus
            Timestamp = Get-Date
        }
        
        # Generate report filename
        $reportFile = Join-Path $OutputPath "ServerMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        
        # Generate HTML report
        if (New-HTMLReport -MonitoringData $monitoringData -OutputFile $reportFile) {
            Write-Log "Monitoring report generated: $reportFile" -Level "INFO"
            
            # Send email if configured and there are alerts
            if ($EmailReport) {
                Send-EmailAlert -MonitoringData $monitoringData -ReportPath $reportFile
            }
        }
        
        # Cleanup old reports
        Remove-OldReports
        
        # Summary
        $alertSummary = $script:Alerts | Group-Object Severity | ForEach-Object { "$($_.Count) $($_.Name)" }
        Write-Log "Monitoring completed. Alerts: $($alertSummary -join ', ')" -Level "INFO"
        
        return $monitoringData
    }
    catch {
        Write-Log "Critical error in monitoring: $($_.Exception.Message)" -Level "ERROR"
        Add-Alert -Category "System" -Severity "HIGH" -Message "Monitoring script error" -Details $_.Exception.Message
        return $null
    }
}

#endregion

#region Main Execution

# Main script execution
try {
    # Check if running as administrator
    if (-not (Test-Administrator)) {
        Write-Warning "This script requires administrator privileges for full functionality."
        Write-Warning "Some monitoring features may not work correctly."
    }
    
    # Load configuration file if specified
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        try {
            $customConfig = Get-Content $ConfigPath | ConvertFrom-Json -AsHashtable
            foreach ($key in $customConfig.Keys) {
                $script:Config[$key] = $customConfig[$key]
            }
            Write-Log "Configuration loaded from: $ConfigPath" -Level "INFO"
        }
        catch {
            Write-Log "Failed to load configuration file: $($_.Exception.Message)" -Level "WARN"
        }
    }
    
    # Start monitoring
    Write-Log "Server Monitor Script v1.0 starting..." -Level "INFO"
    Write-Log "Output Path: $OutputPath" -Level "INFO"
    Write-Log "Continuous Mode: $Continuous" -Level "INFO"
    
    if ($Continuous) {
        Write-Log "Starting continuous monitoring (Interval: $Interval seconds)" -Level "INFO"
        Write-Log "Press Ctrl+C to stop monitoring" -Level "INFO"
        
        while ($true) {
            $results = Start-ServerMonitoring
            
            if ($results) {
                $alertCount = $script:Alerts.Count
                $criticalCount = ($script:Alerts | Where-Object { $_.Severity -eq "HIGH" }).Count
                Write-Console "`n=== Monitoring Cycle Complete ===" -ForegroundColor Cyan
                Write-Console "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
                Write-Console "Total Alerts: $alertCount" -ForegroundColor $(if ($alertCount -gt 0) { "Yellow" } else { "Green" })
                Write-Console "Critical Alerts: $criticalCount" -ForegroundColor $(if ($criticalCount -gt 0) { "Red" } else { "Green" })
                Write-Console "CPU: $($results.Performance.CPU.CPUUsagePercent)% | Memory: $($results.Performance.Memory.MemoryUsagePercent)%" -ForegroundColor White
                Write-Console "Next check in $Interval seconds...`n" -ForegroundColor Gray
            }
            
            Start-Sleep -Seconds $Interval
        }
    }
    else {
        # Single run
        $results = Start-ServerMonitoring
        
        if ($results) {
            Write-Console "`n=== Monitoring Summary ===" -ForegroundColor Cyan
            Write-Console "Server: $($results.SystemInfo.ComputerName)" -ForegroundColor White
            Write-Console "Total Alerts: $($script:Alerts.Count)" -ForegroundColor $(if ($script:Alerts.Count -gt 0) { "Yellow" } else { "Green" })
            Write-Console "CPU Usage: $($results.Performance.CPU.CPUUsagePercent)%" -ForegroundColor White
            Write-Console "Memory Usage: $($results.Performance.Memory.MemoryUsagePercent)%" -ForegroundColor White
            
            if ($script:Alerts.Count -gt 0) {
                Write-Console "`nAlerts Generated:" -ForegroundColor Yellow
                foreach ($alert in $script:Alerts | Sort-Object Severity -Descending) {
                    $color = switch ($alert.Severity) {
                        'HIGH' { 'Red' }
                        'MEDIUM' { 'Yellow' }
                        default { 'White' }
                    }
                    Write-Console "  [$($alert.Severity)] $($alert.Category): $($alert.Message)" -ForegroundColor $color
                }
            }
        }
    }
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}
finally {
    Write-Log "=== Server Monitoring Ended ===" -Level "INFO"
}

#endregion




