# ==============================================================================
# SCRIPT: Sentinel-Register-Task.ps1
# ==============================================================================

$TaskName = "SentinelMediaSync"
$ScriptFolder = $PSScriptRoot
$ScriptPath = Join-Path $ScriptFolder "Start-SentinelSync.ps1"
$XmlPath = Join-Path $ScriptFolder "Sentinel-Daily-Deployment.xml"

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "MISSION ABORTED: This script must be run with Administrator privileges."
    return
}

if (-not (Test-Path $XmlPath)) {
    Write-Host "ERROR: Could not find XML at $XmlPath" -ForegroundColor Red
    return
}

# Read XML and inject current folder paths dynamically
[xml]$taskXml = Get-Content $XmlPath
$taskXml.Task.Actions.Exec.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
$taskXml.Task.Actions.Exec.WorkingDirectory = "$ScriptFolder"

# Save temporary modified XML
$TempXml = Join-Path $env:TEMP "SentinelTempTask.xml"
$taskXml.Save($TempXml)

# Clean up existing task if present
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Register the Task
try {
    Register-ScheduledTask -Xml (Get-Content $TempXml | Out-String) -TaskName $TaskName -ErrorAction Stop
    Write-Host "MISSION SUCCESSFUL" -ForegroundColor Cyan
    Write-Host "Task '$TaskName' registered successfully."
} catch {
    Write-Error "Task registration failed: $_"
}

Write-Host "Script Target: $ScriptPath"