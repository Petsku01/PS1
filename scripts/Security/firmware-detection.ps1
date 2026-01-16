<#
.SYNOPSIS
Detects system firmware type (BIOS or UEFI).

.DESCRIPTION
Uses multiple detection methods (environment variables, registry, WMI) to determine
whether the system is using legacy BIOS or modern UEFI firmware. Useful for
deployment and troubleshooting scenarios.

.PARAMETER AsObject
Return results as PowerShell object instead of formatted table.

.EXAMPLE
.\firmware-detection.ps1
Displays firmware detection results in table format.

.EXAMPLE
.\firmware-detection.ps1 -AsObject
Returns custom object with detection results.

.NOTES
Requires PowerShell 7.5 for ternary operator support.
Secure Boot status is used as primary UEFI indicator.

.LINK
https://docs.microsoft.com/en-us/windows-hardware/design/device-experiences/oem-uefi
#>

#Requires -Version 7.5

# FirmwareDetection.ps1 - Firmware Type Detection Script
# Version: 3.0 (Optimized for 2026: Ternary operators, minimal pipeline)
# Requires: PowerShell 7.5+
# Usage: .\FirmwareDetection.ps1 -AsObject

[CmdletBinding()]
param(
    [System.Management.Automation.SwitchParameter]$AsObject
)

$results = @{}

# Method 1: Environment Variable
$results['EnvCheck'] = $env:firmware_type ? $env:firmware_type : 'Unknown'

# Method 2: Registry Check
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control'
$secureBoot = Get-ItemProperty -Path $regPath -Name 'SecureBoot' -ErrorAction SilentlyContinue
$results['RegCheck'] = $secureBoot.SecureBoot -eq 1 ? 'UEFI' : 'BIOS'

# Method 3: Confirm-SecureBootUEFI Cmdlet
try {
    $results['CmdletCheck'] = Confirm-SecureBootUEFI ? 'UEFI' : 'BIOS'
} catch {
    $results['CmdletCheck'] = 'Unknown'
}

# Method 4: Panther Folder (for install type)
$pantherPath = Join-Path -Path $env:SystemRoot -ChildPath "Panther\setupact.log"
if (Test-Path $pantherPath) {
    $logContent = Get-Content $pantherPath
    $results['PantherCheck'] = $logContent -match 'Detected boot environment: UEFI' ? 'UEFI' : 'BIOS'
} else {
    $results['PantherCheck'] = 'Unknown'
}

if ($AsObject) {
    return $results
} else {
    return $results | Format-Table -Property @{Name='Method';Expression={$_.Key}}, @{Name='Type';Expression={$_.Value}}
}
