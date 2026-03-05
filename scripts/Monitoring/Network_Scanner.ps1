#Requires -Version 5.1
<#
.SYNOPSIS
    Local network scanner - ping sweep + optional hostname resolution

.DESCRIPTION
    Scans a given IPv4 subnet range, detects responding hosts and (optionally)
    resolves their hostnames. Writes results to CSV.
    Compatible with PowerShell 5.1 and 7+ 

.PARAMETER Subnet
    Subnet prefix including trailing dot (example: "192.168.1.")

.PARAMETER Start
    First host number (1-254)

.PARAMETER End
    Last host number (1-254)

.PARAMETER OutputCsv
    Output CSV path

.PARAMETER LogPath
    Optional path for error/warning log

.PARAMETER InterfaceAlias
    Optional - filter network interface by name (wildcards allowed)

.PARAMETER ThrottleLimit
    Max concurrent pings (PS7+ only). Default 20

.PARAMETER TimeoutMs
    Ping timeout in milliseconds (default 1000)

.PARAMETER NoDns
    Skip hostname resolution (faster, especially in restricted networks)

.EXAMPLE
    .\NetworkScanner.ps1 -Subnet 192.168.1.

.EXAMPLE
    .\NetworkScanner.ps1 -Subnet 10.10.10. -Start 50 -End 150 -NoDns

.EXAMPLE
    .\NetworkScanner.ps1 -InterfaceAlias "*Wi-Fi*" -ThrottleLimit 32
#>
[CmdletBinding()]
param (
    [string]$Subnet,

    [ValidateRange(1,254)]
    [int]$Start = 1,

    [ValidateRange(1,254)]
    [int]$End = 254,

    [string]$OutputCsv = "NetworkScan_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [string]$LogPath = "NetworkScan_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",

    [string]$InterfaceAlias,

    [ValidateRange(4,100)]
    [int]$ThrottleLimit = 20,

    [ValidateRange(400,3000)]
    [int]$TimeoutMs = 1000,

    [switch]$NoDns
)

begin {
    $ErrorActionPreference = 'Stop'

    # ------------------- Subnet detection -------------------
    if (-not $Subnet) {
        try {
            $params = @{
                AddressFamily = 'IPv4'
                ErrorAction   = 'Stop'
            }

            if ($InterfaceAlias) {
                $params['InterfaceAlias'] = $InterfaceAlias
            }

            $ip = Get-NetIPAddress @params |
                Where-Object {
                    $_.IPAddress -notmatch '^(127\.|169\.254\.)'
                } |
                Select-Object -First 1 -ExpandProperty IPAddress

            if (-not $ip) {
                throw "No suitable IPv4 address found"
            }

            $Subnet = $ip -replace '\.\d+$','.'
            Write-Host "Using subnet: $Subnet" -ForegroundColor Cyan
        }
        catch {
            Write-Warning "Could not auto-detect subnet: $($_.Exception.Message)"
            Write-Warning "Please provide -Subnet parameter"
            exit 1
        }
    }
    else {
        if ($Subnet -notmatch '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}$') {
            Write-Warning "Subnet should look like '192.168.1.' (with trailing dot)"
            exit 1
        }
    }

    if ($Start -gt $End) {
        Write-Warning "Start > End  swapping"
        $Start, $End = $End, $Start
    }

    Write-Host "Target: ${Subnet}${Start}  ${Subnet}${End}" -ForegroundColor Cyan
    Write-Host "Output: $OutputCsv" -ForegroundColor DarkCyan
    if ($LogPath) { Write-Host "Log:    $LogPath" -ForegroundColor DarkCyan }

    $total = $End - $Start + 1
    $results = [System.Collections.Generic.List[PSObject]]::new()
    $onlineIPs = [System.Collections.Generic.List[string]]::new()
}

process {
    $isPS7 = $PSVersionTable.PSVersion.Major -ge 7
    $timeoutSec = [math]::Ceiling($TimeoutMs / 1000)

    Write-Host "Timeout: $TimeoutMs ms  ($timeoutSec sec)" -ForegroundColor DarkGray

    if ($isPS7) {
        Write-Host "Using parallel ping sweep (PowerShell 7+)" -ForegroundColor Green

        $range = $Start..$End

        $parallelResults = $range | ForEach-Object -Parallel {
            $subnet = $using:Subnet
            $timeout = $using:timeoutSec
            $ip = "$subnet$_"
            try {
                if (Test-Connection -TargetName $ip -Count 1 -Quiet -IPv4 -TimeoutSeconds $timeout -ErrorAction Stop) { $ip }
            }
            catch {
                $null = $_ # Host unreachable - expected for offline IPs
            }
        } -ThrottleLimit $ThrottleLimit
        
        foreach ($ip in $parallelResults) {
            if ($ip) { $onlineIPs.Add($ip) }
        }
    }
    else {
        Write-Host "Sequential scan (PowerShell 5.1)" -ForegroundColor Yellow

        $counter = 0

        for ($i = $Start; $i -le $End; $i++) {
            $counter++
            $pct = [math]::Round($counter / $total * 100, 1)

            Write-Progress -Activity "Ping sweep" -Status "$counter/$total ($pct%)" -PercentComplete $pct

            $ip = "${Subnet}$i"

            if (Test-Connection $ip -Count 1 -Quiet -Delay ($timeoutSec) ) {
                $onlineIPs.Add($ip)
            }
        }
        Write-Progress -Activity "Ping sweep" -Completed
    }

    # ------------------- DNS resolution phase (sequential) -------------------
    if (-not $NoDns -and $onlineIPs.Count -gt 0) {
        Write-Host "`nResolving hostnames for $($onlineIPs.Count) online host(s)..." -ForegroundColor Cyan

        foreach ($ip in $onlineIPs) {
            $obj = [PSCustomObject]@{
                IPAddress = $ip
                Hostname  = 'Unknown'
                Resolved  = $false
                Timestamp = [datetime]::Now
            }

            try {
                $entry = [System.Net.Dns]::GetHostEntry($ip)
                $obj.Hostname = $entry.HostName
                $obj.Resolved = $true
            }
            catch [System.Net.Sockets.SocketException] {
                $null = $_ # DNS resolution failed - keep 'Unknown' hostname
            }

            $results.Add($obj)
        }
    }
    else {
        # No DNS requested  just list online IPs
        foreach ($ip in $onlineIPs) {
            $results.Add(
                [PSCustomObject]@{
                    IPAddress = $ip
                    Hostname  = 'N/A'
                    Resolved  = $false
                    Timestamp = [datetime]::Now
                }
            )
        }
    }
}

end {
    if ($results.Count -eq 0) {
        Write-Host "`nNo responding hosts found." -ForegroundColor DarkYellow
    }
    else {
        Write-Host "`nFound $($results.Count) responding host(s):" -ForegroundColor Green
        $results | Sort-Object IPAddress | Format-Table -AutoSize

        try {
            $results | Sort-Object IPAddress |
                Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force
            Write-Host "Results saved  $OutputCsv" -ForegroundColor Cyan
        }
        catch {
            Write-Warning "Could not write CSV: $($_.Exception.Message)"
        }
    }

    if ($LogPath -and (Test-Path $LogPath)) {
        Write-Host "Log file created: $LogPath" -ForegroundColor DarkGray
    }
}



