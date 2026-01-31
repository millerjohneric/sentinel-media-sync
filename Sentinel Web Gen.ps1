# ==============================================================================
# Sentinel Web Gen v17.4 [THE GEEK MODULAR]
# ==============================================================================
# Updates: Fixed missing Overwrite variable.
#          Full integration with Template Engine.
# ==============================================================================

# --- IMPORT CORE LIBRARY ---
$CorePath = Join-Path $PSScriptRoot 'Sentinel-Core.ps1'
if (Test-Path $CorePath) {
    . $CorePath
} else {
    Write-Error "CRITICAL: Sentinel-Core.ps1 not found at $CorePath"
    exit
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location -Path $PSScriptRoot -ErrorAction SilentlyContinue

if (-not (Get-Module -ListAvailable powershell-yaml)) { Install-Module -Name powershell-yaml -Scope CurrentUser -Force }
Import-Module powershell-yaml

# --- IMPORT CORE & SECRETS ---
. "$PSScriptRoot\Sentinel-Core.ps1"
$SecretsPath = Join-Path $PSScriptRoot '.secure\email-settings.ps1'
if (Test-Path $SecretsPath) { . $SecretsPath }

$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# --- CONFIG & LOGGING ---
$ConfigFilePath = Join-Path $PSScriptRoot 'config.yml'
$YamlData = Get-Content $ConfigFilePath -Raw | ConvertFrom-Yaml

$ConfigLogDir = $YamlData.Settings.LogPath
if (-not (Test-Path $ConfigLogDir)) { New-Item $ConfigLogDir -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $ConfigLogDir 'Sentinel_Web_Gen.log'
Start-Transcript -Path $LogFile -Append

# --- INITIALIZATION ---
$DryRun = $YamlData.Settings.DryRun
$GlobalOverwrite = $YamlData.Settings.Overwrite -eq $true
$SafeWidth = if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $Host.UI.RawUI.WindowSize.Width - 5 } else { 110 }
$WebLocations = $YamlData.Locations | Where-Object { $null -ne $_.Template }
$stats = [PSCustomObject]@{ Scanned=0; Created=0; Updated=0; Skipped=0; Errors=0; Categories=0; Orphans=0 }
$WebChangeLog = New-Object System.Collections.Generic.List[PSCustomObject]
$TargetSitePath = $null

# --- PHASE 0: MASTER PLAN ---
Write-Host "`nPHASE 0: Path Readiness (DryRun=$DryRun)..." -ForegroundColor White
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))
$LocObjects = $YamlData.Locations | ForEach-Object { [PSCustomObject]$_ }
Write-SentinelPhase0 -Locations $LocObjects -IsWebGen $true
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))
# --- PHASE 1: GENERATE ---
Write-Host "`nPHASE 1: GENERATING WEB CONTENT..." -ForegroundColor Cyan

$TotalFiles = 0
foreach ($loc in $WebLocations) {
    if (Test-Path $loc.Path) { $TotalFiles += (Get-ChildItem $loc.Path -Recurse -File | Where-Object { $_.Name -notmatch 'index.md|_category_.yml' }).Count }
}

foreach ($loc in $WebLocations) {
    if (-not (Test-Path $loc.Path)) { continue }
    if ($loc.AutoStart -eq $true) { $TargetSitePath = $loc.SitePath }

    $DocTarget = Join-Path $loc.SitePath (Join-Path "docs" $loc.Name)

    Get-ChildItem $loc.Path -Recurse -File | Where-Object { $_.Name -notmatch 'index.md|_category_.yml' } | ForEach-Object {
        $file = $_
        $stats.Scanned++
        Write-SentinelOdometer -Tag 'PROCESS' -Source $loc.Name -Path $file.Name -Current $stats.Scanned -Total $TotalFiles

        $Result = Build-WebPageFromTemplate `
            -SourceFile $file `
            -TargetFolder $DocTarget `
            -TemplateType $loc.Template `
            -Overwrite $GlobalOverwrite

        switch ($Result) {
            'CREATED' { $stats.Created++ }
            'UPDATED' { $stats.Updated++ }
            'SKIPPED' { $stats.Skipped++ }
            'ERROR'   { $stats.Errors++ }
        }

        if ($Result -ne 'SKIPPED') {
            $WebChangeLog.Add([PSCustomObject]@{ File=$file.Name; Source=$loc.Name; Action=$Result })
        }
    }
}

Clear-SentinelOdometer
Write-Host "  >> [PROCESS ] SUCCESS: " -NoNewline -ForegroundColor Green
Write-Host "Generated $($stats.Created + $stats.Updated) pages from $($stats.Scanned) sources." -ForegroundColor Gray

# --- MISSION REPORT ---
$Report = @"
Sentinel Web Gen Report
----------------------------------
Total Scanned:  $($stats.Scanned)
Pages Created:  $($stats.Created)
Pages Updated:  $($stats.Updated)
Errors:         $($stats.Errors)
----------------------------------
Duration: $($globalStopwatch.Elapsed.ToString("hh\:mm\:ss"))
"@

Write-Host "`n$Report" -ForegroundColor Gray
Send-SentinelReport -ReportBody $Report -JobName "Web Gen"

if ($null -ne $TargetSitePath -and -not $DryRun) { AutoStartWebSite -Path $TargetSitePath }
Stop-Transcript