# ==============================================================================
# Sentinel Media Sync v17.0 [THE GEEK ULTIMATE]
# ==============================================================================
# ==============================================================================
# PYCHARM & POWERSHELL 5.1 COMPATIBILITY LAYER
# ==============================================================================
# Force session to UTF-8 for Emojis and File Writing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Use Hex codes for icons to prevent "ðŸ" artifacts in the script editor
$Global:Icons = @{
    Arrow    = [char]0x2192 # →
    Broom    = [char]0x232B # ⌫ (Broom/Erase proxy for PS 5.1)
    Rocket   = [char]0x21AC # ↬ (Rocket/Launch proxy)
    Check    = [char]0x221A # √
    Warning  = '!!'
}


# --- IMPORT CORE LIBRARY (STRICT SCOPE) ---
$CoreFile = Join-Path $PSScriptRoot "Sentinel-Core.ps1"
if (Test-Path $CoreFile) { . $CoreFile } else { Write-Error "Core Missing: $CoreFile"; exit }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location -Path $PSScriptRoot -ErrorAction SilentlyContinue

if (-not (Get-Module -ListAvailable powershell-yaml)) { Install-Module -Name powershell-yaml -Scope CurrentUser -Force }
Import-Module powershell-yaml

# --- CONFIG & LOGGING ---
$ConfigFilePath = Join-Path $PSScriptRoot 'config.yml'
$YamlData = Get-Content $ConfigFilePath -Raw | ConvertFrom-Yaml
$ConfigLogDir = Join-Path $PSScriptRoot $YamlData.Settings.'LogPath'
if (-not (Test-Path $ConfigLogDir)) { New-Item $ConfigLogDir -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $ConfigLogDir 'Sentinel_Media_Sync.log'

# --- LOG ROTATION (10MB Limit) ---
if (Test-Path $LogFile) {
    $LogSize = (Get-Item $LogFile).Length / 1MB
    if ($LogSize -gt 10) {
        Write-Host "  [CLEANUP] Log exceeds 10MB. Rotating..." -ForegroundColor Gray
        $OldLog = $LogFile + ".bak"
        if (Test-Path $OldLog) { Remove-Item $OldLog -Force }
        Move-Item -Path $LogFile -Destination $OldLog -Force
    }
}

# Now start the fresh transcript
Start-Transcript -Path $LogFile -Append
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# --- DATA CLASS ---
class SentinelLocation {
    [string]$Path; [string]$Name; [string]$Role; [bool]$Enabled; [bool]$PurgeOrphan; [int]$Depth
    SentinelLocation([hashtable]$config) {
        $this.Path = if ($config['Path']) { $config['Path'].Replace('/', '\').TrimEnd('\') } else { '' }
        $this.Name = $config['Name']; $this.Role = $config['Role']
        $this.Depth = if ($null -ne $config['MonitorDepth']) { $config['MonitorDepth'] } else { 1 }
        $this.Enabled = ($this.Depth -ge 0)
        $this.PurgeOrphan = if ($null -ne $config['PurgeOrphan']) { [bool]$config['PurgeOrphan'] } else { $false }
    }
}

$Locations = $script:YamlData.Locations | ForEach-Object { [SentinelLocation]::new($_) }
$ActiveLocs = $Locations | Where-Object { $_.Enabled }
$lookupTable = @{}; $stats = [PSCustomObject]@{ Scanned=0; Moved=0; AtHome=0; Purged=0; Errors=0 }
$DryRun = $script:YamlData.Settings.DryRun
$RawWidth = if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $Host.UI.RawUI.WindowSize.Width } else { 120 }
$SafeWidth = if ($RawWidth -lt 80) { 80 } else { $RawWidth - 5 }

# --- HELPERS ---
function Get-MediaDate {
    param($file)
    if ($file.Name -match '(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})') {
        try { return Get-Date -Year $Matches.year -Month $Matches.month -Day $Matches.day -Hour 0 -Minute 0 -Second 0 } catch {}
    }
    return $file.CreationTime
}

# --- SECRETS ---
$SecretsPath = Join-Path $PSScriptRoot '.secure\email-settings.ps1'
if (Test-Path $SecretsPath) { . $SecretsPath }

# --- PHASE 0: MASTER PLAN ---
# Call the new helper from the library
$SafeWidth = Get-SentinelWidth

Write-Host "`nPHASE 0: Path Readiness (DryRun=$DryRun)..." -ForegroundColor White

# Ensure the multiplier is never less than 1
$DashCount = if ($SafeWidth -gt 10) { $SafeWidth - 5 } else { 80 }
$Divider = '   + ' + ('-' * $DashCount)

Write-Host $Divider
Write-SentinelPhase0 -Locations $Locations
Write-Host $Divider

# --- PHASE 1: MAPPING ---
Write-Host "`nPHASE 1: MAPPING MEDIA..." -ForegroundColor Cyan
$inv = @{ Img=0; RAW=0; Vid=0; Aud=0; Side=0 }
$ImgExts = $script:YamlData.FileTypes.Images; $RawExts = $script:YamlData.FileTypes.RAWs
$VidExts = $script:YamlData.FileTypes.Videos; $AudExts = $script:YamlData.FileTypes.Audio
$MediaExts = $ImgExts + $RawExts + $VidExts + $AudExts + '.xmp'

foreach ($loc in $ActiveLocs) {
    if (-not (Test-Path $loc.Path)) { continue }
    $allFiles = Get-ChildItem -Path $loc.Path -File -Recurse:($loc.Depth -gt 1)
    foreach ($file in $allFiles) {
        $ext = $file.Extension.ToLower()
        if ($MediaExts -notcontains $ext) { continue }
        Write-SentinelOdometer -Tag 'SCAN' -Source $loc.Name -Path $file.Name
        if ($ImgExts -contains $ext) { $inv.Img++ }
        elseif ($RawExts -contains $ext) { $inv.RAW++ }
        elseif ($VidExts -contains $ext) { $inv.Vid++ }
        elseif ($AudExts -contains $ext) { $inv.Aud++ }
        elseif ($ext -eq '.xmp') { $inv.Side++ }
        $fileKey = "$($file.Length)_$($file.Name)"
        if (-not $lookupTable.ContainsKey($fileKey)) { $lookupTable[$fileKey] = New-Object System.Collections.Generic.List[System.IO.FileInfo] }
        $lookupTable[$fileKey].Add($file); $stats.Scanned++
    }
}
Clear-SentinelOdometer
$F_Img = Format-SentinelNum $inv.Img
$F_Raw = Format-SentinelNum $inv.RAW
$F_Vid = Format-SentinelNum $inv.Vid
$F_Aud = Format-SentinelNum $inv.Aud
$F_Side = Format-SentinelNum $inv.Side
Write-Host "  >> [SCAN    ] SUCCESS: Images: $F_Img | RAWs: $F_Raw | Videos: $F_Vid | Audio: $F_Aud | Sidecars: $F_Side" -ForegroundColor Gray

# --- PHASE 2: ROUTING ---
Write-Host "`nPHASE 2: ROUTING MEDIA..." -ForegroundColor White
$p2Counter = 0; $TotalGroups = $lookupTable.Count; $LastDir = ''
$p2Inv = @{ Img=0; RAW=0; Vid=0; Aud=0; Side=0 }

foreach ($key in $lookupTable.Keys) {
    $p2Counter++; $group = $lookupTable[$key]; $master = $group[0]
    $ext = $master.Extension.ToLower()
    $origin = $ActiveLocs | Where-Object { $master.FullName.StartsWith($_.Path) } | Select-Object -First 1

    if ($null -eq $origin -or ($origin.Role -match 'Web|Hybrid' -and $origin.Role -ne 'InPlace_Archive')) { continue }

    if ($master.DirectoryName -ne $LastDir) {
        Write-SentinelOdometer -Tag 'ROUTING' -Source $origin.Name -Path $master.DirectoryName -Current $p2Counter -Total $TotalGroups
        $LastDir = $master.DirectoryName
    }

    $mDate = Get-MediaDate -file $master
    $datePath = Join-Path $mDate.ToString('yyyy') $mDate.ToString('MM MMMM')

    if ($origin.Role -eq 'InPlace_Archive') {
        $Rel = $master.FullName.Replace($origin.Path, '').TrimStart('\'); $Parts = $Rel -split '\\'
        $targetRoot = if ($Parts.Count -ge 2) { Join-Path $origin.Path (Join-Path $Parts[0] $Parts[1]) } else { $master.DirectoryName }
        if ($master.DirectoryName -match '\\\d{4}\\\d{2}\s\w+$') { $stats.AtHome++; continue }
    } else {
        $RoleType = if ($RawExts -contains $ext) { 'RAW_Archive' } else { 'Photo_Archive' }
        $targetRoot = ($ActiveLocs | Where-Object { $_.Role -eq $RoleType } | Select-Object -First 1).Path
    }

    if ($targetRoot) {
        $finalPath = Join-Path $targetRoot $datePath
        if (-not $DryRun) {
            if (-not (Test-Path $finalPath)) { New-Item $finalPath -ItemType Directory -Force | Out-Null }
            try {
                Move-Item $master.FullName $finalPath -Force -ErrorAction Stop
                $stats.Moved++
                if ($ImgExts -contains $ext) { $p2Inv.Img++ }
                elseif ($RawExts -contains $ext) { $p2Inv.RAW++ }
                elseif ($VidExts -contains $ext) { $p2Inv.Vid++ }
                elseif ($AudExts -contains $ext) { $p2Inv.Aud++ }
                elseif ($ext -eq '.xmp') { $p2Inv.Side++ }
            } catch { $stats.Errors++ }
        }
    }
}
Clear-SentinelOdometer
$F_Img = Format-SentinelNum $inv.Img
$F_Raw = Format-SentinelNum $inv.RAW
$F_Vid = Format-SentinelNum $inv.Vid
$F_Aud = Format-SentinelNum $inv.Aud
$F_Side = Format-SentinelNum $inv.Side
Write-Host "  >> [SCAN    ] SUCCESS: Images: $F_Img | RAWs: $F_Raw | Videos: $F_Vid | Audio: $F_Aud | Sidecars: $F_Side" -ForegroundColor Gray

# --- PHASE 3: REUNITING & ORPHAN CHECK ---
if ($script:YamlData.'Settings'.'DisableSidecarReunite' -eq $true) {
    Write-Host "`nPHASE 3: REUNITING SIDECARS (DISABLED via Config)" -ForegroundColor Yellow
} else {
    Write-Host "`nPHASE 3: REUNITING SIDECARS..." -ForegroundColor Cyan
    $p3Counter = 0
    $p3Inv = @{ 'Reunited'=0; 'Purged'=0 }
    $TotalDirs = 0

    # Calculate denominator for odometer
    foreach ($loc in $ActiveLocs) {
        if ($loc.Role -match 'Archive' -and (Test-Path $loc.Path)) {
            $TotalDirs += (Get-ChildItem $loc.Path -Recurse -Directory).Count
        }
    }

    foreach ($loc in $ActiveLocs) {
        if ($loc.Role -notmatch 'Archive' -or -not (Test-Path $loc.Path)) { continue }

        Get-ChildItem $loc.Path -Recurse -Directory | ForEach-Object {
            $p3Counter++
            $CurrentDir = $_.FullName
            Write-SentinelOdometer -Tag 'REUNITE' -Source $loc.Name -Path $CurrentDir -Current $p3Counter -Total $TotalDirs

            $Sidecars = Get-ChildItem $CurrentDir -File -Filter *.xmp
            foreach ($s in $Sidecars) {
                $Buddy = Get-SentinelBuddy -Sidecar $s -SearchRoot $loc.Path

                if ($Buddy) {
                    # REUNITE: Found parent media in a different folder
                    if ($s.DirectoryName -ne $Buddy.DirectoryName -and -not $DryRun) {
                        try {
                            Move-Item $s.FullName $Buddy.DirectoryName -Force -ErrorAction Stop
                            $p3Inv.'Reunited'++
                        } catch { $stats.Errors++ }
                    }
                } elseif ($loc.PurgeOrphan -eq $true) {
                    # PURGE: No parent found and PurgeOrphan is enabled for this location
                    if (-not $DryRun) {
                        try {
                            Remove-Item $s.FullName -Force -ErrorAction Stop
                            $p3Inv.'Purged'++
                        } catch { $stats.Errors++ }
                    }
                }
            }
        }
    }
    Clear-SentinelOdometer
    Write-Host "  >> [REUNITE ] SUCCESS: " -NoNewline -ForegroundColor Green
    Write-Host "Reunited: $($p3Inv.'Reunited') | Purged Orphans: $($p3Inv.'Purged')" -ForegroundColor Gray
}

# --- PHASE 4: JUNK PURGE ---
if ($script:YamlData.'Settings'.'DisableJunkPurge' -eq $true) {
    Write-Host "`nPHASE 4: JUNK PURGE (DISABLED via Config)" -ForegroundColor Yellow
} else {
    Write-Host "`nPHASE 4: JUNK PURGE..." -ForegroundColor Red
    $p4Counter = 0; $p4Purged = 0
    $JunkExts = $script:YamlData.'FileTypes'.'Junk'
    $PurgeLocs = $ActiveLocs | Where-Object { $_.Role -match 'Archive' }
    $TotalFilesToPurge = 0
    foreach ($pl in $PurgeLocs) { if (Test-Path $pl.Path) { $TotalFilesToPurge += (Get-ChildItem $pl.Path -Recurse -File).Count } }

    foreach ($loc in $PurgeLocs) {
        if (-not (Test-Path $loc.Path)) { continue }
        Get-ChildItem $loc.Path -Recurse -File | ForEach-Object {
            $p4Counter++; $file = $_
            Write-SentinelOdometer -Tag 'PURGE' -Source $loc.Name -Path $file.Name -Current $p4Counter -Total $TotalFilesToPurge
            if ($JunkExts -contains $file.Extension.ToLower() -and -not $DryRun) {
                try { Remove-Item $file.FullName -Force -ErrorAction Stop; $p4Purged++; $stats.Purged++ } catch { $stats.Errors++ }
            }
        }
    }
    Clear-SentinelOdometer
    Write-Host "  >> [PURGE   ] SUCCESS: Purged $(Format-SentinelNum $p4Purged) Junk Files." -ForegroundColor Gray
}

# --- MISSION REPORT ---
$S3Status = if ($script:YamlData.'Settings'.'DisableSidecarReunite') { "DISABLED" } else { "COMPLETE" }
$S4Status = if ($script:YamlData.'Settings'.'DisableJunkPurge') { "DISABLED" } else { "COMPLETE" }

$Report = @"
Sentinel Sync Mission Report
----------------------------------
Phase 3 (Sidecars): $S3Status
Phase 4 (Junk):     $S4Status
----------------------------------
Total Scanned:  $(Format-SentinelNum $stats.Scanned)
Items Moved:    $(Format-SentinelNum $stats.Moved)
Already Home:   $(Format-SentinelNum $stats.AtHome)
Purged Files:   $(Format-SentinelNum $stats.Purged)
Errors:         $(Format-SentinelNum $stats.Errors)
----------------------------------
Duration: $($globalStopwatch.Elapsed.ToString('hh\:mm\:ss'))
"@

Write-Host "`n$Report" -ForegroundColor Gray
Send-SentinelReport -ReportBody $Report -JobName "Sync"
Stop-Transcript