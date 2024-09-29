# CheckForUpdates.ps1
# Checks for and installs Windows updates

# Import the Update session COM object
$updateSession = New-Object -ComObject Microsoft.Update.Session

# Create an update searcher
$updateSearcher = $updateSession.CreateUpdateSearcher()

# Search for updates
$searchResult = $updateSearcher.Search("IsInstalled=0")

if ($searchResult.Updates.Count -eq 0) {
    Write-Host "No updates available."
} else {
    Write-Host "$($searchResult.Updates.Count) updates found. Installing..."
    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

    foreach ($update in $searchResult.Updates) {
        $updatesToInstall.Add($update)
    }

    $installer = $updateSession.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $installationResult = $installer.Install()

    Write-Host "Installation result: $($installationResult.ResultCode)"
}
