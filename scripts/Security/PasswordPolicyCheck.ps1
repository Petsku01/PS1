<#
.SYNOPSIS
Reports on Active Directory password policies and expiration status.

.DESCRIPTION
Queries all enabled AD users and retrieves password policy details including
expiration dates, never-expires status, and required fields. Supports filtering
by search base and inclusion of accounts with non-expiring passwords.

.PARAMETER SearchBase
Distinguished Name to scope the query. Default: current domain.

.PARAMETER IncludeNeverExpires
Include accounts with passwords set to never expire.

.EXAMPLE
.\PasswordPolicyCheck.ps1

.EXAMPLE
.\PasswordPolicyCheck.ps1 -SearchBase "OU=Sales,DC=company,DC=com" -IncludeNeverExpires

.NOTES
Requires ActiveDirectory module (RSAT).
Query uses discoverable writable domain controller.

.LINK
https://docs.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
#>

#Requires -Version 5.1
#Requires -Modules ActiveDirectory

# Now the caller decides what is "bad"  not the script
param(
    [string]$SearchBase = (Get-ADDomain).DistinguishedName,
    [switch]$IncludeNeverExpires
)

$results = Get-ADUser -Filter {Enabled -eq $true} -SearchBase $SearchBase -Properties `
    Name,SamAccountName,PasswordLastSet,PasswordNeverExpires,PasswordNotRequired,
    UserAccountControl,msDS-UserPasswordExpiryTimeComputed,msDS-AssignedAuthPolicy `
    -Server (Get-ADDomainController -Discover -Writable).HostName |

    ForEach-Object {
        $expiry = $null
        if ($_.'msDS-UserPasswordExpiryTimeComputed' -gt 0) {
            $expiry = [datetime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed')
        }

        [pscustomobject]@{
            Name                  = $_.Name
            SamAccountName        = $_.SamAccountName
            PasswordLastSet       = $_.PasswordLastSet
            PasswordAgeDays       = if($_.PasswordLastSet) {(New-TimeSpan $_.PasswordLastSet).Days} else {$null}
            Expires               = $expiry
            DaysUntilExpiry       = if($expiry) {($expiry-(Get-Date)).Days} else {$null}
            NeverExpires          = $_.PasswordNeverExpires
            PasswordNotRequired   = $_.PasswordNotRequired
            ReversibleEncryption = [bool]($_.UserAccountControl -band 128)
        }
    }


$results | Sort-Object Name

