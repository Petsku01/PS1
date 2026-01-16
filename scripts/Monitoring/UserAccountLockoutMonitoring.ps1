<#
.SYNOPSIS
Monitors Active Directory user account lockouts with alerting.

.DESCRIPTION
Continuously monitors domain for user account lockouts and near-lockout events.
Maintains state file to track processed events. Supports configurable check intervals
and logging for compliance and troubleshooting.

.PARAMETER None
Configuration via $Config hash table at script start.

.EXAMPLE
.\UserAccountLockoutMonitoring.ps1
(Runs as background monitoring service)

.NOTES
Requires ActiveDirectory PowerShell module.
Maintains state file for event deduplication.
Creates log directory automatically.

.LINK
https://docs.microsoft.com/en-us/powershell/module/activedirectory/search-adaccount
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

# Import CommonFunctions for standardized logging if available
Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction SilentlyContinue

# UserAccountLockoutMonitor.ps1 -v 1.01
# -pk


# Configurable parameters
$Config = @{
    CheckIntervalSec = 600          # 10 minutes
    LogDirectory     = Join-Path $PSScriptRoot "LockoutLogs"
    StateFile        = Join-Path $PSScriptRoot "LockoutMonitor.state"
}

# Ensure log directory exists
if (-not (Test-Path $Config.LogDirectory)) { New-Item -Path $Config.LogDirectory -ItemType Directory -Force | Out-Null }

# Load or initialize last processed timestamp
if (Test-Path $Config.StateFile) {
    $LastCheck = [DateTime]::FromFileTime((Get-Content $Config.StateFile -Raw))
} else {
    $LastCheck = (Get-Date).AddMinutes(-5)
}

# Admin + module check (unchanged, but shorter)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")) {
    Write-Error "Run as Administrator"; exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

function Get-CurrentLogFile {
    Join-Path $Config.LogDirectory ("UserLockouts_{0:yyyyMMdd}.csv" -f (Get-Date))
}

function Write-LogHeader ($File) {
    if (-not (Test-Path $File)) {
        "Time,Username,CallerComputer" | Out-File $File -Encoding utf8 -Force
    }
}

function Save-State {
    [DateTime]::UtcNow.ToFileTime().ToString() | Out-File $Config.StateFile -Force
}

Write-Host "Account Lockout Monitor started  checking every $($Config.CheckIntervalSec)s" -ForegroundColor Cyan

while ($true) {
    $Now = Get-Date
    $LogFile = Get-CurrentLogFile
    Write-LogHeader $LogFile

    try {
        $Events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4740
            StartTime = $LastCheck
        } -ErrorAction Stop -MaxEvents 1000
    } catch {
        Write-Warning "Get-WinEvent failed: $($_.Exception.Message)"
        Start-Sleep -Seconds $Config.CheckIntervalSec
        continue
    }

    foreach ($e in $Events) {
        $User    = $e.Properties[0].Value.Trim()
        $Caller  = $e.Properties[1].Value.TrimEnd('$') -replace '^-$','<unknown>'

        if (-not $User) { continue }

        $Line = '"{0}","{1}","{2}"' -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $User, $Caller
        $Line | Out-File $LogFile -Append -Encoding utf8

        Write-Host "$($e.TimeCreated.ToString('HH:mm:ss'))  LOCKOUT  $User  (from $Caller)" -ForegroundColor Yellow
    }

    $LastCheck = $Now
    Save-State
    Start-Sleep -Seconds $Config.CheckIntervalSec
}



