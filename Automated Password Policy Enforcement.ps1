# PasswordPolicyCheck.ps1
# Checks for non-compliant user passwords

Import-Module ActiveDirectory

# Define criteria for password complexity
$minLength = 8
$mustContainUppercase = $true
$mustContainLowercase = $true
$mustContainNumber = $true
$mustContainSpecialChar = $true

# Function to check password compliance
function Check-PasswordCompliance {
    $users = Get-ADUser -Filter * -Property PasswordLastSet, PasswordNeverExpires, Name

    foreach ($user in $users) {
        $password = $user.Password
        if ($user.PasswordNeverExpires) {
            continue
        }
        
        if ($password.Length -lt $minLength -or
            ($mustContainUppercase -and $password -notmatch '[A-Z]') -or
            ($mustContainLowercase -and $password -notmatch '[a-z]') -or
            ($mustContainNumber -and $password -notmatch '[0-9]') -or
            ($mustContainSpecialChar -and $password -notmatch '[!@#$%^&*(),.?":{}|<>]')) {
            Write-Host "User $($user.Name) does not meet password policy requirements."
        }
    }
}

# Execute the check
Check-PasswordCompliance
