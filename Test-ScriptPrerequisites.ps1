<#
.SYNOPSIS
Validates runtime prerequisites for PowerShell scripts in this repository.

.DESCRIPTION
Scans .ps1 files for #Requires statements and checks whether the current environment
meets those prerequisites (PowerShell version, administrator elevation, and modules).
Produces a pass/fail matrix so you can see which scripts are runnable right now.

.PARAMETER RootPath
Root folder to scan. Defaults to current directory.

.PARAMETER IncludeTests
Include files under tests/ in the scan.

.PARAMETER Json
Emit structured JSON output for CI/pipeline consumption.

.EXAMPLE
.\Test-ScriptPrerequisites.ps1

.EXAMPLE
.\Test-ScriptPrerequisites.ps1 -RootPath . -IncludeTests

.EXAMPLE
.\Test-ScriptPrerequisites.ps1 -Json
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RootPath = ".",

    [Parameter()]
    [switch]$IncludeTests,

    [Parameter()]
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Parse-RequireDirectives {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $content = Get-Content -Path $FilePath -ErrorAction Stop
    $requiresLines = @($content | Where-Object { $_ -match '^\s*#Requires\b' })

    $requirements = [ordered]@{
        RequiresAdmin = $false
        MinVersion    = $null
        Modules       = @()
    }

    foreach ($line in $requiresLines) {
        if ($line -match '-RunAsAdministrator') {
            $requirements.RequiresAdmin = $true
        }

        if ($line -match '-Version\s+([0-9]+(?:\.[0-9]+){0,3})') {
            try {
                $version = [Version]$Matches[1]
                if ($null -eq $requirements.MinVersion -or $version -gt $requirements.MinVersion) {
                    $requirements.MinVersion = $version
                }
            }
            catch {
                # Ignore malformed version values
            }
        }

        if ($line -match '-Modules\s+(.+)$') {
            $rawModules = $Matches[1]
            $moduleNames = @($rawModules -split ',' |
                ForEach-Object { ($_ -replace '[\[\]"''`$]', '').Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            if (@($moduleNames).Count -gt 0) {
                $requirements.Modules += $moduleNames
            }
        }
    }

    $requirements.Modules = @($requirements.Modules | Select-Object -Unique)
    return [PSCustomObject]$requirements
}

if (-not (Test-Path -Path $RootPath)) {
    throw "Root path does not exist: $RootPath"
}

$resolvedRoot = (Resolve-Path -Path $RootPath).Path
$isAdmin = Test-IsAdministrator
$currentVersion = $PSVersionTable.PSVersion

$scripts = Get-ChildItem -Path $resolvedRoot -Recurse -File -Filter *.ps1 |
    Where-Object {
        if ($IncludeTests) { return $true }
        $_.FullName -notmatch '\\tests\\'
    } |
    Sort-Object FullName

$results = foreach ($script in $scripts) {
    $req = Parse-RequireDirectives -FilePath $script.FullName

    $issues = @()

    if ($req.RequiresAdmin -and -not $isAdmin) {
        $issues += 'Requires administrator privileges'
    }

    if ($null -ne $req.MinVersion -and $currentVersion -lt $req.MinVersion) {
        $issues += "Requires PowerShell $($req.MinVersion) or newer"
    }

    $missingModules = @()
    foreach ($moduleName in $req.Modules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        $issues += "Missing module(s): $($missingModules -join ', ')"
    }

    $relativePath = $script.FullName.Substring($resolvedRoot.Length).TrimStart('\') -replace '\\','/'

    [PSCustomObject]@{
        Status     = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
        Script     = $relativePath
        Requires   = @(
            if ($req.RequiresAdmin) { 'Admin' }
            if ($null -ne $req.MinVersion) { "PS>=$($req.MinVersion)" }
            if ($req.Modules.Count -gt 0) { "Modules: $($req.Modules -join ', ')" }
        ) -join '; '
        BlockingBy = if ($issues.Count -eq 0) { '' } else { $issues -join ' | ' }
    }
}

$passCount = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count

$sortedResults = @($results | Sort-Object Status, Script)

if ($Json) {
    $payload = [PSCustomObject]@{
        Environment = [PSCustomObject]@{
            PowerShellVersion = $currentVersion.ToString()
            IsAdministrator   = $isAdmin
            RootPath          = $resolvedRoot
        }
        Summary = [PSCustomObject]@{
            ScriptsChecked = $results.Count
            PassCount      = $passCount
            FailCount      = $failCount
        }
        Results = $sortedResults
    }

    $payload | ConvertTo-Json -Depth 6
}
else {
    Write-Output "Environment: PowerShell $currentVersion | Admin: $isAdmin"
    Write-Output "Scripts checked: $($results.Count) | PASS: $passCount | FAIL: $failCount"
    Write-Output ''

    $sortedResults | Format-Table Status, Script, Requires, BlockingBy -AutoSize
}

if ($failCount -gt 0) {
    exit 1
}

exit 0