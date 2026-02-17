# ==============================================================================
# Sentinel Media Sync v17.3 [WEBSITE ROLE EXCLUSION]
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Import Core & Config
$CoreFile = Join-Path $PSScriptRoot 'Sentinel-Core.ps1'
if (Test-Path $CoreFile) { . $CoreFile } else { Write-Error 'Core Missing'; exit }

Import-Module powershell-yaml
# Updated config file name
$ConfigFilePath = Join-Path $PSScriptRoot 'Sentinel-Config.yml'
$YamlData = Get-Content $ConfigFilePath -Raw | ConvertFrom-Yaml
$WebLocations = $YamlData.Locations
$GlobalSettings = $YamlData.Settings

$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$stats = @{ Scanned = 0; Moved = 0; AtHome = 0; Purged = 0; Errors = 0 }

# --- PHASE 0: READINESS ---
Write-SentinelPhase0 -Locations $WebLocations -JobType 'Web'

# --- PHASE 1: DIRECTORY VALIDATION ---
Write-Host "`nPHASE 1: Validating Directory Integrity..." -ForegroundColor White
foreach ($loc in $WebLocations) {
    if (-not (Test-Path $loc.Path)) {
        Write-Host "  $($Global:Icons.Arrow) [MISSING] $($loc.Name): Creating..." -ForegroundColor Yellow
        New-Item -Path $loc.Path -ItemType Directory -Force | Out-Null
    }
}

# --- PHASE 2: MEDIA RE-ORGANIZATION ---
Write-Host "`nPHASE 2: Organizing Media Assets..." -ForegroundColor White

# Explicitly ignore 'Website' roles to prevent accidental file moves into dev environments
$PickupLocs = $WebLocations | Where-Object { $_.Role -eq 'Pickup' -and $_.Role -ne 'Website' }

 foreach ($loc in $PickupLocs) {
    $Files = Get-ChildItem -Path $loc.Path -File -Recurse | Where-Object {
        -not (Test-SentinelExclusion -Path $_.FullName)
    }
    $count = 0
    foreach ($file in $Files) {
        $count++
        $stats.Scanned++
        Write-SentinelOdometer -Tag 'MOVE' -Source $loc.Name -Path $file.Name -Current $count -Total $Files.Count

        # Routing logic remains internal
        $stats.AtHome++
    }
    Write-Host ""
}

# --- PHASE 3: SIDECAR RE-UNIFICATION ---
Write-Host "`nPHASE 3: Re-uniting Sidecar Metadata..." -ForegroundColor White
if ($GlobalSettings.DisableSidecarReunite) {
    Write-Host "  >> Feature disabled in global settings." -ForegroundColor Gray
} else {
    $HybridLocs = $WebLocations | Where-Object { $_.Role -eq 'Hybrid_Archive' }
    foreach ($loc in $HybridLocs) {
        $Sidecars = Get-ChildItem -Path $loc.Path -Filter '*.yml' -Recurse
        $count = 0
        foreach ($sidecar in $Sidecars) {
            $count++
            $Buddy = Get-SentinelBuddy -Sidecar $sidecar -SearchRoot $loc.Path
            $StatusTag = if ($Buddy) { 'SYNC' } else { 'ORPHAN' }

            Write-SentinelOdometer -Tag $StatusTag -Source $loc.Name -Path $sidecar.Name -Current $count -Total $Sidecars.Count
        }
        Write-Host ""
    }
}

# --- PHASE 4: JUNK PURGING ---
Write-Host "`nPHASE 4: Purging Junk Files..." -ForegroundColor White
if ($GlobalSettings.DisableJunkPurge) {
    Write-Host "  >> Feature disabled in global settings." -ForegroundColor Gray
} else {
    foreach ($loc in $WebLocations) {
        $Junk = Get-ChildItem -Path $loc.Path -Include Thumbs.db, .DS_Store, *.tmp -Recurse -Force
        $count = 0
        foreach ($file in $Junk) {
            $count++
            Write-SentinelOdometer -Tag 'PURGE' -Source $loc.Name -Path $file.Name -Current $count -Total $Junk.Count
            Remove-Item $file.FullName -Force
            $stats.Purged++
        }
        if ($count -gt 0) { Write-Host "" }
    }
}

# --- PHASE 5: MISSION REPORT ---
$Duration = $globalStopwatch.Elapsed.ToString('mm\:ss')
Send-SentinelNotification -Stats $stats -Duration $Duration -JobName 'MediaSync'

$Summary = "Scanned: $($stats.Scanned) | Moved: $($stats.AtHome) | Purged: $($stats.Purged) | Time: $Duration"
Write-Host "`n[SUCCESS] Mission complete in $Duration." -ForegroundColor Green