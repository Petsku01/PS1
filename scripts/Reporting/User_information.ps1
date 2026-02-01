#Requires -Version 5.1

<#
.SYNOPSIS
Displays detailed information about local or Active Directory user accounts.

.DESCRIPTION
Queries user information from local system accounts and/or Active Directory.
Supports multiple lookup modes and output formats. Works on Windows 10+/Server 2016+
with optional privilege elevation for comprehensive local account access.

.PARAMETER Username
SAM account name, UPN or local username to query.

.PARAMETER All
Show both local and AD information if both exist.

.PARAMETER PreferAD
If both exist, show only AD information.

.PARAMETER LogPath
Optional path for warning/error log file.

.PARAMETER AsObject
Return raw PSCustomObject(s) instead of formatted output.

.PARAMETER Elevate
Relaunch script as admin if not elevated (for local queries).

.EXAMPLE
.\User_information.ps1 -Username jsmith -All

.EXAMPLE
.\User_information.ps1 -Username "jsmith@company.com" -PreferAD -LogPath "C:\Logs\userinfo.log"

.NOTES
Searches both local and AD sources for maximum information.
Graceful fallback if AD unavailable.

.LINK
https://docs.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({
        if ($_ -match '^[a-zA-Z0-9._@-]+$') { $true }
        else { throw "Invalid characters. Allowed: letters, numbers, . _ @ -" }
    })]
    [string]$Username,

    [switch]$All,

    [switch]$PreferAD,

    [string]$LogPath,

    [switch]$AsObject,

    [switch]$Elevate
)

begin {
    $ErrorActionPreference = 'Stop'
    
    # Import CommonFunctions for standardized logging if available
    Import-Module -Name (Join-Path $PSScriptRoot '..\..\CommonFunctions.psm1') -Force -ErrorAction SilentlyContinue

    function Write-LocalLog {
        param ([string]$Message)
        $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
        Write-Warning $logMsg
        if ($LogPath) {
            # Try to use CommonFunctions if available
            if (Get-Command Write-StandardLog -ErrorAction SilentlyContinue) {
                Write-StandardLog -Message $Message -Level "INFO" -Path $LogPath
            } else {
                $logMsg | Out-File -FilePath $LogPath -Append -Encoding UTF8
            }
        }
    }

    $canLocal = $false
    $canAD    = $false
    $isAdmin  = $false

    # Elevation handling
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if ($Elevate -and -not $isAdmin) {
        Write-Verbose "Relaunching as admin..."
        $relaunchArgs = "-File `"$PSCommandPath`" -Username `"$Username`""
        if ($All) { $relaunchArgs += " -All" }
        if ($PreferAD) { $relaunchArgs += " -PreferAD" }
        if ($LogPath) { $relaunchArgs += " -LogPath `"$LogPath`"" }
        if ($AsObject) { $relaunchArgs += " -AsObject" }

        Start-Process powershell.exe -Verb RunAs -ArgumentList $relaunchArgs
        return
    }

    #  Check capabilities 
    # Local users
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $canLocal = $true
    }

    # Active Directory
    if (Get-Module -ListAvailable ActiveDirectory -ErrorAction SilentlyContinue) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false
            # Better connectivity check: try to get current domain
            $null = Get-ADDomain -ErrorAction Stop -WarningAction SilentlyContinue
            $canAD = $true
        }
        catch {
            Write-LocalLog "AD module loaded but connectivity test failed: $($_.Exception.Message)"
        }
    }

    #  Inform user about capabilities 
    Write-Verbose "Local query: $canLocal $(if(-not $isAdmin){'(needs admin)'})"
    Write-Verbose "AD query: $canAD"
}

process {
    $results = [System.Collections.Generic.List[PSObject]]::new()

    #  1. Try Active Directory 
    if ($canAD) {
        try {
            # Use -Filter for better handling of ambiguous identities
            $filter = if ($Username -match '@') { "UserPrincipalName -eq '$Username'" } else { "SamAccountName -eq '$Username'" }
            $adUsers = Get-ADUser -Filter $filter -Properties DisplayName,Enabled,LastLogonDate,PasswordLastSet,Description,UserPrincipalName,SamAccountName,DistinguishedName -ErrorAction Stop

            if ($adUsers.Count -gt 1) {
                Write-LocalLog "Multiple AD users found for '$Username'. Using first match."
            }

            if ($adUsers) {
                $adUser = $adUsers[0]
                $results.Add([PSCustomObject]@{
                    Source        = 'Active Directory'
                    Name          = $adUser.Name
                    DisplayName   = $adUser.DisplayName
                    SamAccountName= $adUser.SamAccountName
                    UPN           = $adUser.UserPrincipalName
                    Enabled       = $adUser.Enabled
                    LastLogonDate = $adUser.LastLogonDate
                    PwdLastSet    = $adUser.PasswordLastSet
                    Description   = $adUser.Description
                    DN            = $adUser.DistinguishedName
                })

                if (-not $All -and $PreferAD) { break }
            }
        }
        catch {
            Write-LocalLog "AD query failed: $($_.Exception.Message)"
        }
    }

    #  2. Try local user 
    if ($canLocal -and $isAdmin) {
        try {
            $localUsers = Get-LocalUser -Name $Username -ErrorAction Stop

            if ($localUsers.Count -gt 1) {
                Write-LocalLog "Multiple local users found for '$Username'. Using first match."
            }

            if ($localUsers) {
                $local = $localUsers[0]
                $results.Add([PSCustomObject]@{
                    Source        = 'Local'
                    Name          = $local.Name
                    DisplayName   = $local.FullName
                    SamAccountName= $local.Name
                    UPN           = $null
                    Enabled       = $local.Enabled
                    LastLogonDate = $local.LastLogon
                    PwdLastSet    = $local.PasswordLastSet
                    Description   = $local.Description
                    DN            = $null
                })
            }
        }
        catch {
            Write-LocalLog "Local query failed: $($_.Exception.Message)"
        }
    }
    elseif ($canLocal -and -not $isAdmin) {
        Write-LocalLog "Local query skipped: not running as admin"
    }
}

end {
    if ($results.Count -eq 0) {
        Write-Host "`nUser '$Username' not found." -ForegroundColor DarkYellow

        if (-not $canLocal -and -not $canAD) {
            Write-Host "No query capabilities available." -ForegroundColor DarkGray
        }
        elseif (-not $canLocal) {
            Write-Host "Local queries not available." -ForegroundColor DarkGray
        }
        elseif (-not $isAdmin) {
            Write-Host "Local check skipped (not admin)." -ForegroundColor DarkGray
        }
        elseif (-not $canAD) {
            Write-Host "AD queries not available." -ForegroundColor DarkGray
        }
    }
    else {
        if ($AsObject) {
            $results
        }
        else {
            Write-Host "`nFound $($results.Count) match(es):" -ForegroundColor Green
            $results | Format-List
        }
    }

    if ($LogPath -and (Test-Path $LogPath)) {
        Write-Verbose "Log saved to $LogPath"
    }
}

