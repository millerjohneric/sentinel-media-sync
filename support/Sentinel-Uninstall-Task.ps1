# ==============================================================================
# SCRIPT: Sentinel-Uninstall-Task.ps1
# ==============================================================================
$TaskName = "SentinelMediaSync"

Write-Host "DE-COMMISSIONING: $TaskName..." -ForegroundColor Yellow

# Check if the task exists before trying to delete
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "MISSION ABORTED: Scheduled task has been removed." -ForegroundColor Cyan
} else {
    Write-Host "NO MISSION FOUND: Task '$TaskName' does not exist." -ForegroundColor Gray
}

Write-Host "`nPress any key to close..."
$null = [Console]::ReadKey($true)