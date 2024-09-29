# UserAccountLockoutMonitor.ps1
# Monitors user account lockouts in Active Directory

Import-Module ActiveDirectory

# Define the output file for logging
$logFile = "UserAccountLockouts.csv"

# Function to check for locked out accounts
function Check-Lockouts {
    $lockouts = Get-EventLog -LogName Security -InstanceId 4740 -After (Get-Date).AddMinutes(-30) | 
                Select-Object TimeGenerated, Message

    foreach ($lockout in $lockouts) {
        $userName = $lockout.Message -replace '.*\s+\[(.*?)\].*', '$1' # Extract username from message
        $time = $lockout.TimeGenerated
        # Log to CSV
        $entry = [PSCustomObject]@{
            Time       = $time
            Username   = $userName
        }
        $entry | Export-Csv -Path $logFile -Append -NoTypeInformation
    }
}

# Check for lockouts every 10 minutes
while ($true) {
    Check-Lockouts
    Start-Sleep -Seconds 600
}
