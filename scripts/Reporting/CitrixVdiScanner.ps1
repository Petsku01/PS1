<#
.SYNOPSIS
Citrix Virtual Apps & Desktops issue scanner for on-premises and cloud deployments.

.DESCRIPTION
Scans Citrix infrastructure for common issues including slow logons, high latency,
black screens, and failed connections. Supports both on-premises and Citrix Cloud
environments. Zero console spam design with CSV export for reporting.

.PARAMETER AdminAddress
Citrix Delivery Controller address (on-premises).

.PARAMETER HoursBack
Hours of logs to scan. Default: 6 hours.

.PARAMETER CsvPath
Output path for CSV report.

.EXAMPLE
.\CitrixVdiScanner.ps1 -AdminAddress "ddc01.company.local" -HoursBack 6 -CsvPath "C:\Reports\CitrixIssues.csv"

.EXAMPLE
.\CitrixVdiScanner.ps1 -Cloud -CsvPath "C:\Reports\CloudIssues.csv"

.NOTES
Requires Citrix PowerShell SDK.
Minimal output by design for automation scenarios.

.LINK
https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/sdk-api
#>

#Requires -Version 5.1
<#
.SYNOPSIS
    Citrix Virtual Apps & Desktops 

.DESCRIPTION
    Cloud scanner for slow logons, high latency, black screens and failed connections.
    Works on-premises AND Citrix Cloud. Zero Write-Host spam. Designed for automation in mind.

.AUTHOR
    -pk

.VERSION
    3.0  December 2025

.HOW TO USE

 On-prem
Find-CitrixVdiIssues -AdminAddress "ddc01.company.local" -HoursBack 6 -CsvPath "C:\Reports\CitrixIssues_$(Get-Date -F yyyyMMdd_HHmm).csv"

Citrix Cloud (recommended way)
$token = ConvertTo-SecureString "eyJ..." -AsPlainText -Force
Find-CitrixVdiIssues -BearerToken $token -CustomerId "customer123" -Quiet | Export-Csv daily.csv -NoTypeInformation

Scheduled task (silent)
Find-CitrixVdiIssues -AdminAddress ddc01 -Quiet | Where-Object Type -like "*Failure*" | Send-MailMessage ...
#>

function Find-CitrixVdiIssues {
    [CmdletBinding(DefaultParameterSetName = 'OnPrem')]
    param (
        # On-premises Delivery Controller
        [Parameter(Mandatory, ParameterSetName = 'OnPrem')]
        [string]$AdminAddress,

        # Citrix Cloud (use one of these)
        [Parameter(Mandatory, ParameterSetName = 'CloudBearer')]
        [securestring]$BearerToken,

        [Parameter(Mandatory, ParameterSetName = 'CloudFile')]
        [string]$SecureClientFile,

        [Parameter(ParameterSetName = 'CloudBearer')]
        [Parameter(ParameterSetName = 'CloudFile')]
        [string]$CustomerId,

        # Time window to scan (default = last 24 hours)
        [int]$HoursBack = 24,

        # Thresholds (tweak per environment)
        [int]$LogonSeconds       = 120,
        [int]$InteractiveSeconds = 60,
        [int]$LatencyMs          = 200,
        [int]$BandwidthBps       = 2000,   # < 2 kbps on a session >10 min = suspicious
        [int]$MinSessionMinutes  = 10,

        # Output
        [switch]$Quiet,
        [string]$CsvPath
    )

    #region Module Loading (modern way  works everywhere)
    $Modules = @(
        'Citrix.Broker.Commands'
        'Citrix.DelegatedAdmin.Commands'
        'Citrix.Common.Commands'
    )

    foreach ($mod in $Modules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Error "Required module '$mod' not found. Install the latest Citrix Virtual Apps and Desktops Remote PowerShell SDK."
            return
        }
        Import-Module $mod -ErrorAction Stop -Verbose:$false
    }
    #endregion

    #region Authentication & Connection
    $CommonParams = @{}

    switch ($PSCmdlet.ParameterSetName) {
        'OnPrem' {
            $CommonParams.AdminAddress = $AdminAddress
            if (-not $Quiet) { Write-Verbose "Connecting to on-prem DDC: $AdminAddress" }
        }
        'CloudBearer' {
            $CommonParams.BearerToken = $BearerToken
            $CommonParams.CustomerId  = $CustomerId
            if (-not $Quiet) { Write-Verbose "Connecting to Citrix Cloud (Bearer token)" }
        }
        'CloudFile' {
            $CommonParams.SecureClientFile = $SecureClientFile
            if ($CustomerId) { $CommonParams.CustomerId = $CustomerId }
            if (-not $Quiet) { Write-Verbose "Connecting to Citrix Cloud (SecureClient file)" }
        }
    }
    #endregion

    $Since = (Get-Date).AddHours(-$HoursBack)
    $FilterSession = "StartDate -ge '$($Since.ToString('yyyy-MM-ddTHH:mm:ssK'))'"
    $FilterConnLog = "BrokeringTime -ge '$($Since.ToString('yyyy-MM-ddTHH:mm:ssK'))'"

    $Issues = [System.Collections.ArrayList]::new()

    #region 1. Active/Connected Sessions (real-time metrics)
    if (-not $Quiet) { Write-Verbose "Querying active sessions since $Since ..." }
    try {
        $Sessions = Get-BrokerSession @CommonParams -Filter $FilterSession -Property `
            UserName, MachineName, SessionKey, StartDate, LogOnDuration,
            ProtocolLatencyAverage, ProtocolBandwidthAverage -ErrorAction Stop
    }
    catch {
        Write-Warning "Get-BrokerSession failed: $_"
        $Sessions = @()
    }

    foreach ($s in $Sessions) {
        $ageMin = [math]::Round(((Get-Date) - $s.StartDate).TotalMinutes)

        if ($s.LogOnDuration -and $s.LogOnDuration.TotalSeconds -gt $LogonSeconds) {
            [void]$Issues.Add([pscustomobject]@{
                PSTypeName   = 'Citrix.Issue.SlowLogon'
                Type         = 'Slow Logon'
                User         = $s.UserName
                Machine      = $s.MachineName
                SessionKey   = $s.SessionKey
                ReportedAt   = Get-Date
                Value        = "{0:N0}s" -f $s.LogOnDuration.TotalSeconds
                Threshold    = "$LogonSeconds`s"
                Source       = 'Live Session'
            })
        }

        if ($s.ProtocolLatencyAverage -gt $LatencyMs) {
            [void]$Issues.Add([pscustomobject]@{
                PSTypeName = 'Citrix.Issue.HighLatency'
                Type       = 'High Latency'
                User       = $s.UserName
                Machine    = $s.MachineName
                SessionKey = $s.SessionKey
                ReportedAt = Get-Date
                Value      = "$($s.ProtocolLatencyAverage) ms"
                Threshold  = "$LatencyMs ms"
                Source     = 'Live Session'
            })
        }

        if ($ageMin -ge $MinSessionMinutes -and $s.ProtocolBandwidthAverage -lt $BandwidthBps) {
            [void]$Issues.Add([pscustomobject]@{
                PSTypeName = 'Citrix.Issue.BlackScreen'
                Type       = 'Potential Black/Frozen Screen'
                User       = $s.UserName
                Machine    = $s.MachineName
                SessionKey = $s.SessionKey
                ReportedAt = Get-Date
                Value      = "$($s.ProtocolBandwidthAverage) bps"
                Threshold  = "< $BandwidthBps bps (age $ageMin min)"
                Source     = 'Live Session'
            })
        }
    }
    #endregion

    #region 2. Connection Logs (authoritative slow logon & failures)
    if (-not $Quiet) { Write-Verbose "Querying connection logs since $Since ..." }
    try {
        $ConnLogs = Get-BrokerConnectionLog @CommonParams -Filter $FilterConnLog -Property `
            BrokeringUserName, MachineName, BrokeringTime, LogOnDuration, InteractiveDuration,
            VMStartDuration, BrokeringDuration, ConnectionFailureReason, FailureDate -MaxRecordCount 50000 -ErrorAction Stop
    }
    catch {
        Write-Warning "Get-BrokerConnectionLog failed: $_"
        $ConnLogs = @()
    }

    foreach ($c in $ConnLogs) {
        if ($c.FailureDate) {
            [void]$Issues.Add([pscustomobject]@{
                PSTypeName = 'Citrix.Issue.ConnectionFailure'
                Type       = 'Connection Failure'
                User       = $c.BrokeringUserName
                Machine    = $c.MachineName
                SessionKey = $null
                ReportedAt = $c.FailureDate
                Value      = $c.ConnectionFailureReason
                Threshold  = 'N/A'
                Source     = 'Connection Log'
            })
            continue
        }

        if ($c.LogOnDuration -and $c.LogOnDuration.TotalSeconds -gt $LogonSeconds) {
            [void]$Issues.Add([pscustomobject]@{
                PSTypeName = 'Citrix.Issue.SlowLogon'
                Type       = 'Slow Logon'
                User       = $c.BrokeringUserName
                Machine    = $c.MachineName
                SessionKey = $null
                ReportedAt = $c.BrokeringTime
                Value      = "{0:N0}s (Brokering {1:N0}s | VMStart {2:N0}s)" -f
                            $c.LogOnDuration.TotalSeconds,
                            $c.BrokeringDuration.TotalSeconds,
                            $c.VMStartDuration.TotalSeconds
                Threshold  = "$LogonSeconds`s"
                Source     = 'Connection Log'
            })
        }

        if ($c.InteractiveDuration -and $c.InteractiveDuration.TotalSeconds -gt $InteractiveSeconds) {
            [void]$Issues.Add([pscustomobject]@{
                PSTypeName = 'Citrix.Issue.BlackScreen'
                Type       = 'Delayed Interactive (Black Screen)'
                User       = $c.BrokeringUserName
                Machine    = $c.MachineName
                SessionKey = $null
                ReportedAt = $c.BrokeringTime
                Value      = "{0:N0}s" -f $c.InteractiveDuration.TotalSeconds
                Threshold  = "$InteractiveSeconds`s"
                Source     = 'Connection Log'
            })
        }
    }
    #endregion

    #region Output
    if (-not $Quiet) {
        if ($Issues.Count -eq 0) {
            Write-Host "No issues detected in the last $HoursBack hours." -ForegroundColor Green
        }
        else {
            Write-Host "`nFound $($Issues.Count) issue(s) in the last $HoursBack hours:" -ForegroundColor Red
            $Issues | Sort-Object ReportedAt -Descending |
                      Format-Table Type, User, Machine, Value, Source -AutoSize
        }
    }

    if ($CsvPath) {
        try {
            $parent = Split-Path $CsvPath -Parent
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $Issues | Sort-Object ReportedAt -Descending |
                    Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
            Write-Verbose "CSV report saved to $CsvPath"
        }
        catch {
            Write-Error "Failed to write CSV: $_"
        }
    }

    # Always return objects for piping / monitoring systems
    return $Issues
}
#endregion

