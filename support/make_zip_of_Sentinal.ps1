$Source = $PSScriptRoot
$Destination = Join-Path $env:USERPROFILE "Desktop\Sentinel_v9.1_Backup.zip"
$Exclude = @("*.log", "*.zip")

Write-Host "Packing Sentinel Suite for transport..." -ForegroundColor Cyan
Get-ChildItem -Path $Source -Exclude $Exclude | Compress-Archive -DestinationPath $Destination -Force
Write-Host "MISSION PACKED: Check your Desktop for Sentinel_v9.1_Backup.zip" -ForegroundColor Green