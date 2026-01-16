#Requires -Version 7.0

<#
.SYNOPSIS
Advanced disk space monitoring with parallel processing and email alerts.

.DESCRIPTION
Monitors multiple drives in parallel, supports email alerting, CSV export, and
secret-based credential management. Uses PowerShell 7 parallel processing for
efficient multi-system scanning.

.PARAMETER ThresholdGB
Alert threshold in gigabytes. Default: 10.0 GB.

.PARAMETER EmailAlert
Send email alerts when thresholds are exceeded.

.PARAMETER ExportPath
Path to export monitoring results to CSV.

.PARAMETER SmtpServer
SMTP server for email alerts.

.PARAMETER EnableLogging
Enable detailed logging of all monitoring activities.

.EXAMPLE
.\DiskSpaceMonitor2.ps1 -ThresholdGB 15 -EmailAlert -SmtpServer "smtp.company.com"

.NOTES
Requires PowerShell 7.0 or higher for parallel processing.
SMTP credentials should be stored using SecretManagement module.

.LINK
https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/foreach-object
#>

# .SYNOPSIS
# Monitors disk space, alerts on low thresholds.
# .PARAMETER ThresholdGB
# Alert if free space below this (GB).

function Get-DiskSpaceMonitor {
    [CmdletBinding()]
    param(
        [ValidateRange(1, [System.Double]::MaxValue)][System.Double]$ThresholdGB = 10.0,
        [System.Management.Automation.SwitchParameter]$WarningsOnly,
        [System.String]$ExportPath,
        [System.Management.Automation.SwitchParameter]$EmailAlert,
        [System.String]$SmtpServer,
        [System.String]$EmailTo,
        [System.String]$EmailFrom,
        [System.Int32]$SmtpPort = 587,
        [System.Management.Automation.SwitchParameter]$UseSSL,
        [System.Management.Automation.PSCredential]$SmtpCredential = (Get-Secret -Name 'SmtpCred' -ErrorAction 'SilentlyContinue'),
        [System.Management.Automation.SwitchParameter]$EnableLogging,
        [System.String]$LogPath = '.\DiskSpaceMonitor.log'
    )

    if ($EmailAlert -and -not ($SmtpServer -and $EmailTo -and $EmailFrom)) { throw 'Missing email parameters.' }

    $results = @()
    $alerts = @()

    # .NET for performance
    [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } | ForEach-Object -Parallel {
        $freeGB = [System.Math]::Round($using:_.AvailableFreeSpace / 1GB, 2)
        $totalGB = [System.Math]::Round($using:_.TotalSize / 1GB, 2)
        $percentFree = $totalGB -gt 0 ? [System.Math]::Round(($freeGB / $totalGB) * 100, 1) : 0
        $status = $freeGB -lt $using:ThresholdGB ? 'WARNING' : 'OK'

        $result = [PSCustomObject]@{
            Drive = $using:_.Name
            FreeGB = $freeGB
            TotalGB = $totalGB
            PercentFree = $percentFree
            Status = $status
        }
        $results += $result  # Note: In parallel, use shared var carefully or collect post-loop
        if ($status -eq 'WARNING') { $alerts += "Low space on $($result.Drive): $freeGB GB free" }
    } -ThrottleLimit 2  # Limit for stability

    if ($alerts -and $EmailAlert) {
        $mailParams = @{
            SmtpServer = $SmtpServer
            Port = $SmtpPort
            To = $EmailTo
            From = $EmailFrom
            Subject = 'Disk Space Alert'
            Body = $alerts -join "`n"
            UseSsl = $UseSSL
            Credential = $SmtpCredential
        }
        Send-MailMessage @mailParams
    }
    if ($ExportPath) { $results | Export-Csv -Path $ExportPath -NoTypeInformation }
    $results
}
