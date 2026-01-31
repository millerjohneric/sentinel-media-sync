# ==============================================================================
# SCRIPT: Sentinel-Register-Task.ps1
# ==============================================================================
$TaskName = "SentinelMediaSync"
$ScriptFolder = $PSScriptRoot
$ScriptPath = Join-Path $ScriptFolder "Sentinel Media Sync.ps1"
$XmlPath = Join-Path $ScriptFolder "Sentinel-Daily-Deployment.xml"
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
Get-ScheduledTask -TaskName "SentinelMediaSync" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

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

# Register the Task
Register-ScheduledTask -Xml (Get-Content $TempXml | Out-String) -TaskName $TaskName -Force

try {
    Register-ScheduledTask -Xml (Get-Content $TempXml | Out-String) -TaskName "SentinelMediaSync" -ErrorAction Stop
    Write-Host "MISSION SUCCESSFUL" -ForegroundColor Cyan
    Write-Host "Task '$TaskName' registered to run daily at 02:00 AM."
} catch {
    Write-Error "Task registration failed: $_"
}
Write-Host "Script Target: $ScriptPath"