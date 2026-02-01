<#
.SYNOPSIS
Performs automated system maintenance including cleanup and health checks.

.DESCRIPTION
Executes system maintenance operations: cleanup of temporary files, health monitoring,
system backup, and email reporting. Supports configuration via JSON and detailed logging.
Includes WhatIf support for safe previewing.

.PARAMETER Cleanup
Perform temporary file cleanup.

.PARAMETER Monitor
Enable system monitoring mode.

.PARAMETER Backup
Create system backup.

.PARAMETER LogPath
Path to maintenance log file. Default: $env:USERPROFILE\Desktop\SystemMaintenance.log.

.PARAMETER ConfigPath
Path to maintenance configuration JSON. Default: maintenance.config.json.

.PARAMETER EmailTo
Email address for reporting results.

.EXAMPLE
.\SystemMaintenance.ps1 -Cleanup -Monitor -LogPath "C:\Logs\maint.log"

.NOTES
Supports -WhatIf for safe preview of changes.
Configuration stored in JSON format.

.LINK
https://docs.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
#>

#Requires -Version 5.1

# Import CommonFunctions for standardized logging
Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction Stop

function Invoke-SystemMaintenance {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [switch]$Cleanup,
        [switch]$Monitor,
        [switch]$Backup,
        [string]$LogPath = "$env:USERPROFILE\Desktop\SystemMaintenance.log",
        [string]$ConfigPath = "$PSScriptRoot\maintenance.config.json",
        [string]$EmailTo
    )

    $params = @{
        Verbose = $PSBoundParameters['Verbose']
        WhatIf = $PSBoundParameters['WhatIf']
    }

    $isElevated = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isElevated) { Write-Warning 'Limited mode without elevation.' }

    # Load configuration if file exists
    $Config = @{}
    if (Test-Path $ConfigPath) {
        try {
            $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            Write-Warning "Failed to load config from ${ConfigPath}: $_"
        }
    }

    try {
        Write-StandardLog -Message "Started maintenance (Config loaded: $($Config.Count -gt 0))" -Level 'INFO' -Path $LogPath
        $report = ''
        if ($Cleanup) { $report += Invoke-SystemCleanup @params }  # Parallel: $CleanupPaths | ForEach-Object -Parallel { Remove-Item $_ -Recurse -Force } -ThrottleLimit 4
        elseif ($Monitor) { $report += Start-PerformanceMonitor @params }
        elseif ($Backup) { $report += Invoke-SystemBackup @params }
        else { $report += Test-SystemHealth @params }
        if ($EmailTo) { Send-EmailReport -Report $report -To $EmailTo -SmtpCred (Get-Secret -Name 'SmtpCred') @params }  # Use secrets
    } catch {
        Write-StandardLog -Message "Error: $($_.Exception.Message)" -Level 'ERROR' -Path $LogPath
        throw
    } finally {
        Write-StandardLog -Message 'Completed' -Level 'INFO' -Path $LogPath
    }
}

# Remove custom Write-Log function - now using CommonFunctions.Write-StandardLog
