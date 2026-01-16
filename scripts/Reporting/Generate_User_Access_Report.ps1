<#
.SYNOPSIS
Generates a CSV report of Active Directory users and last logon times.

.DESCRIPTION
Queries Active Directory to create a comprehensive report of all user accounts,
their creation dates, and last logon times. Exports results to CSV for analysis
and compliance reporting.

.PARAMETER OutputFile
Path to output CSV file. Default: UserAccessReport.csv.

.EXAMPLE
.\Generate_User_Access_Report.ps1

.EXAMPLE
.\Generate_User_Access_Report.ps1 -OutputFile "C:\Reports\AccessReport.csv"

.NOTES
Requires ActiveDirectory PowerShell module (RSAT).
Must have Read permissions on user objects in Active Directory.

.LINK
https://docs.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
#>

#Requires -Version 5.1
#Requires -Modules ActiveDirectory

# UserAccessReport.ps1
# Purpose: Generates a CSV report of Active Directory user accounts and their last logon times

# Check if the ActiveDirectory module is available
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Host "Error: Failed to load ActiveDirectory module. Ensure RSAT is installed and you have necessary permissions." -ForegroundColor Red
    exit 1
}

# Define the output file path for the CSV report
$outputFile = "UserAccessReport.csv"

# Validate write access to the output file path
try {
    $testPath = [System.IO.Path]::GetDirectoryName($outputFile)
    if ($testPath -eq "") { $testPath = "." } # Handle current directory case
    if (-not (Test-Path $testPath -PathType Container)) {
        Write-Host "Error: Output directory does not exist or is inaccessible." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error: Invalid output file path or insufficient permissions." -ForegroundColor Red
    exit 1
}

# Retrieve all AD user accounts with their LastLogonDate property (more reliable than LastLogon)
try {
    $users = Get-ADUser -Filter * -Property LastLogonDate, LastLogon -ErrorAction Stop | Select-Object Name, LastLogonDate, LastLogon
    if (-not $users) {
        Write-Host "Warning: No user accounts found in Active Directory." -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "Error: Failed to retrieve user accounts from Active Directory. Check permissions or domain connectivity." -ForegroundColor Red
    exit 1
}

# Create a custom report by using LastLogonDate (replicated) or falling back to LastLogon
$report = foreach ($user in $users) {
    $lastLogonDate = if ($user.LastLogonDate) {
        $user.LastLogonDate
    } elseif ($user.LastLogon -and $user.LastLogon -gt 0) {
        try {
            [DateTime]::FromFileTime($user.LastLogon)
        } catch {
            "Invalid LastLogon value"
        }
    } else {
        "Never logged on"
    }
    
    [PSCustomObject]@{
        Name       = $user.Name
        LastLogon  = $lastLogonDate
    }
}

# Export the report to a CSV file
try {
    $report | Export-Csv -Path $outputFile -NoTypeInformation -ErrorAction Stop
    Write-Host "User access report generated: $outputFile" -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to export report to $outputFile. Check file permissions or if the file is in use." -ForegroundColor Red
    exit 1
}
