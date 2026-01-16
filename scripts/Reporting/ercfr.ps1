<#
.SYNOPSIS
Enables and verifies Configuration Manager Remote Control firewall rule.

.DESCRIPTION
Creates necessary firewall rule for SCCM Remote Control operations and verifies
that the Configuration Manager client is installed on the system.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\ercfr.ps1

.NOTES
Requires Administrator privileges.
Configuration Manager installation path is C:\Program Files\Microsoft Configuration Manager.

.LINK
https://docs.microsoft.com/en-us/mem/configmgr/core/clients/deploy/deploy-clients-to-windows-computers
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Script to enable and verify Configuration Manager Remote Control firewall rule and client installation
# Ensures the firewall rule exists for remote control and verifies SCCM client installation

# Enable Remote Control Firewall Rule
# Define the firewall rule name and expected program path
$ruleName = "Configuration Manager Remote Control"
$programPath = Join-Path -Path $env:ProgramFiles -ChildPath "Microsoft Configuration Manager\bin\x64\cmrcservice.exe"

try {
    # Attempt to retrieve the existing firewall rule
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $rule) {
        # Create a new firewall rule if it doesn't exist
        New-NetFirewallRule -DisplayName $ruleName `
                           -Direction Inbound `
                           -Program $programPath `
                           -Action Allow `
                           -Protocol TCP `
                           -LocalPort 2701 `
                           -Profile Domain,Private `
                           -ErrorAction Stop
        Write-Output "Successfully created firewall rule: $ruleName"
    } else {
        Write-Output "Firewall rule '$ruleName' already exists."
    }
}
catch {
    # Handle errors related to firewall rule creation
    Write-Error "Failed to create or verify firewall rule '$ruleName'. Error: $($_.Exception.Message)"
    exit 1
}

# Verify Configuration Manager Client
try {
    # Attempt to retrieve SCCM client information from WMI
    $client = Get-WmiObject -Namespace "root\ccm" -Class SMS_Client -ErrorAction Stop
    if ($client) {
        Write-Output "Configuration Manager client is installed. Client version: $($client.ClientVersion)"
    } else {
        Write-Output "Configuration Manager client is not installed."
    }
}
catch {
    # Handle errors related to WMI query
    Write-Error "Failed to verify Configuration Manager client. Error: $($_.Exception.Message)"
    exit 1
}
