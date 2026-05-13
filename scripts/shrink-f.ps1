# Run as Administrator -- shrinks F: by 150 GB to make room for NixOS

$driveLetter = "F"
$shrinkBytes = 150GB

$partition = Get-Partition -DriveLetter $driveLetter
$currentSize = $partition.Size
$newSize = $currentSize - $shrinkBytes

Write-Host "Disk:     $($partition.DiskNumber) -- Samsung SSD 980 Pro"
Write-Host "Current:  $([math]::Round($currentSize / 1GB, 1)) GB"
Write-Host "New size: $([math]::Round($newSize / 1GB, 1)) GB"
Write-Host "Freeing:  150 GB for NixOS"
Write-Host ""

$supported = Get-PartitionSupportedSize -DriveLetter $driveLetter
if ($newSize -lt $supported.SizeMin) {
    Write-Host "ERROR: Cannot shrink that far. Min size is $([math]::Round($supported.SizeMin / 1GB, 1)) GB"
    exit 1
}

$confirm = Read-Host "Proceed? [y/N]"
if ($confirm -ne "y") { exit 0 }

Resize-Partition -DriveLetter $driveLetter -Size $newSize

Write-Host ""
Write-Host "Done. 150 GB of unallocated space now on Disk $($partition.DiskNumber)."
Write-Host "Verify in Disk Management: diskmgmt.msc"
