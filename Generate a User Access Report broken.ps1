# UserAccessReport.ps1
# Generates a report of user accounts and their last logon times

Import-Module ActiveDirectory

# Define output file
$outputFile = "UserAccessReport.csv"

# Get user accounts and their last logon times
$users = Get-ADUser -Filter * -Property LastLogon | Select-Object Name, LastLogon

# Convert LastLogon from large integer to DateTime
$report = foreach ($user in $users) {
    [PSCustomObject]@{
        Name       = $user.Name
        LastLogon  = [DateTime]::FromFileTime($user.LastLogon)
    }
}

# Export report to CSV
$report | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host "User access report generated: $outputFile"