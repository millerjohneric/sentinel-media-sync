# ==============================================================================
# PHASE 2: CONFIGURE AUTOMATED MISSIONS
# ==============================================================================

# 1. Force Administrative Privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Elevation required. Opening UAC prompt...' -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 2. Define Mission Parameters
$TaskName = 'Sentinel_Midnight_Sync'
$ScriptPath = "C:\Users\mille\Documents\GitHub\sentinel-media-sync\Sentinel Media Sync.ps1"
$Action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 12:00AM

# 3. Attempt Registration
try {
    Write-Host "Registering $TaskName..." -ForegroundColor Cyan

    # Register the task
    Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $TaskName -Description 'Daily synchronization for The Source media archives.' -Force -ErrorAction Stop

    # Verification Check
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Host "SUCCESS: $TaskName scheduled for 12:00 AM daily." -ForegroundColor Green
    }
}
catch {
    Write-Host "FAILURE: Could not register task. Details: $($_.Exception.Message)" -ForegroundColor Red
    Pause
}