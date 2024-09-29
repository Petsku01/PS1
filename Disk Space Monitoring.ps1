# DiskSpaceMonitor.ps1
# Monitors disk space and alerts if below a threshold

# Set the threshold for free space (in GB)
$thresholdGB = 10

# Get disk information
$disks = Get-PSDrive -PSProvider FileSystem

foreach ($disk in $disks) {
    $freeSpaceGB = [math]::round($disk.Free / 1GB, 2)

    if ($freeSpaceGB -lt $thresholdGB) {
        Write-Host "Warning: Disk $($disk.Name) is running low on space. Free space: $freeSpaceGB GB"
    } else {
        Write-Host "Disk $($disk.Name) has sufficient space. Free space: $freeSpaceGB GB"
    }
}
