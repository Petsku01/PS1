#Requires -Version 5.1

<#
.SYNOPSIS
Monitors disk space on all local drives and alerts on low space conditions.

.DESCRIPTION
Iterates through all accessible file system drives and checks free space against a
configurable threshold. Provides visual feedback (colored output) for space status.
Useful for scheduled task monitoring and preventive disk management.

.PARAMETER ThresholdGB
Minimum free space threshold in gigabytes before alerting. Default is 10 GB.

.EXAMPLE
.\Disk_Space_Monitoring.ps1
Monitors all drives with default 10 GB threshold.

.EXAMPLE
.\Disk_Space_Monitoring.ps1 -ThresholdGB 20
Monitors all drives with 20 GB threshold.

.NOTES
Drives without accessible free space information are skipped gracefully.
Output color codes: Green = sufficient, Yellow = warning, Gray = inaccessible.

.LINK
https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-psdrive
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Minimum free space threshold in gigabytes before alerting")]
    [ValidateRange(1, 1000)]
    [int]$ThresholdGB = 10
)

# Retrieve information about all drives with the FileSystem provider (e.g., C:, D:)
$disks = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue

# Iterate through each disk to check its free space
foreach ($disk in $disks) {
    try {
        # Check if the drive is accessible and has free space information
        if ($null -ne $disk.Free) {
            # Convert free space from bytes to gigabytes and round to two decimal places for readability
            $freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
            
            # Check if free space is below the defined threshold
            if ($freeSpaceGB -lt $ThresholdGB) {
                # Output a warning message if free space is below the threshold
                Write-Host "Warning: Disk $($disk.Name) is running low on space. Free space: $freeSpaceGB GB" -ForegroundColor Yellow
            } else {
                # Output a confirmation message if free space is sufficient
                Write-Host "Disk $($disk.Name) has sufficient space. Free space: $freeSpaceGB GB" -ForegroundColor Green
            }
        } else {
            # Skip drives that don't have accessible free space information
            Write-Host "Disk $($disk.Name) is not accessible or does not report free space." -ForegroundColor Gray
        }
    } catch {
        Write-Host "Disk $($disk.Name) could not be checked: $($_.Exception.Message)" -ForegroundColor Gray
    }
}
