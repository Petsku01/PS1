# CheckForUpdates.ps1
<#
.SYNOPSIS
Checks for available Windows updates and installs them automatically.

.DESCRIPTION
This script queries the Windows Update service to find available updates that have not been
installed on the system. It displays the count of available updates and provides an option
to proceed with installation.

.PARAMETER None
This script does not accept parameters.

.EXAMPLE
.\Check for Windows Updates.ps1

.NOTES
Requires Administrator privileges to install updates.
Uses Windows Update COM object for compatibility.

.LINK
https://docs.microsoft.com/en-us/windows/win32/wua_sdk/portal
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# CheckForUpdates.ps1
# Purpose: Checks for available Windows updates and installs them
# Note: it works!

# Create an instance of the Windows Update session COM object to interact with the Windows Update service
$updateSession = New-Object -ComObject Microsoft.Update.Session

# Initializes an update searcher object to query for available updates
$updateSearcher = $updateSession.CreateUpdateSearcher()

# Perform a search for updates that are not yet installed (IsInstalled=0)
$searchResult = $updateSearcher.Search("IsInstalled=0")

# Check if any updates were found
if ($searchResult.Updates.Count -eq 0) {
    # Output a message if no updates are available
    Write-Host "No updates available."
} else {
    # Output the number of updates found and indicate installation is starting
    Write-Host "$($searchResult.Updates.Count) updates found. Installing..."
    
    # Creates a collection object to hold the updates to be installed
    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    
    # Iterate through each update in the search results and add it to the installation collection
    foreach ($update in $searchResult.Updates) {
        $updatesToInstall.Add($update) | Out-Null
    }
    
    # Create an installer object to handle the update installation process
    $installer = $updateSession.CreateUpdateInstaller()
    
    # Assign the collection of updates to the installer
    $installer.Updates = $updatesToInstall
    
    # Executes the installation of the collected updates
    $installationResult = $installer.Install()
    
    # Output the result code of the installation (e.g., 2 = succeeded)
    Write-Host "Installation result: $($installationResult.ResultCode)"
}
