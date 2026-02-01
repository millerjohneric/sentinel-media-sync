# ==============================================================================
# Sentinel Web Gen v17.4 [THE GEEK MODULAR]
# ==============================================================================
# Updates: Fixed missing Overwrite variable.
#          Full integration with Template Engine.
# ==============================================================================
# Force PyCharm/PS 5.1 into UTF-8 mode immediately
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
#$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'


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

# --- IMPORT CORE & SECRETS ---"
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
# --- PHASE 1: GENERATING WEB CONTENT ---
foreach ($loc in $WebLocations) {
    if ($loc.Role -ne 'Hybrid_Archive') { continue }

    if ($null -ne $loc.SitePath) { $TargetSitePath = $loc.SitePath }

    $Exclusions = $YamlData.'Exclusions'
    $ImgExts = $YamlData.'FileTypes'.'Images'
    $EffectiveOverwrite = if ($null -ne $loc.Overwrite) { $loc.Overwrite } else { $GlobalOverwrite }

    # --- PHASE 1A: CATEGORY MAPPING (ALL FOLDERS) ---
    Write-Host "  >> Mapping categories for all folders in $($loc.Name)..." -ForegroundColor Gray

    # Get all subdirectories while strictly respecting your Exclusions list
    $AllFolders = Get-ChildItem -Path $loc.Path -Directory -Recurse | Where-Object {
        $DirPath = $_.FullName
        $IsExcluded = $false
        foreach ($ex in $Exclusions) {
            if ($DirPath -like "*\$ex\*") { $IsExcluded = $true; break }
        }
        -not $IsExcluded
    }

    # Generate category for the Root folder
    Write-SentinelCategoryYaml -FolderPath $loc.Path -FolderName (Split-Path $loc.Path -Leaf) -Force $EffectiveOverwrite

    # Generate categories for all valid subfolders
    foreach ($dir in $AllFolders) {
        Write-SentinelCategoryYaml -FolderPath $dir.FullName -FolderName $dir.Name -Force $EffectiveOverwrite
    }

    # --- PHASE 1B: FILE PROCESSING ---
    $SourceFiles = Get-ChildItem -Path $loc.Path -File -Recurse | Where-Object {
        $FilePath = $_.FullName
        $IsExcluded = $false
        foreach ($ex in $Exclusions) {
            if ($FilePath -like "*\$ex\*") { $IsExcluded = $true; break }
        }
        ($_.Extension -in $ImgExts) -and (-not $IsExcluded)
    }

    foreach ($file in $SourceFiles) {
        $stats.Scanned++
        Write-SentinelOdometer -Tag 'PROCESS' -Source $loc.Name -Path $file.Name -Current $stats.Scanned -Total $SourceFiles.Count

        $Result = Build-WebPageFromTemplate `
            -SourceFile $file `
            -TargetFolder $file.DirectoryName `
            -TemplateType $loc.Template `
            -Overwrite $EffectiveOverwrite
        switch ($Result) {
            'CREATED' { $stats.Created++ }
            'UPDATED' { $stats.Updated++ }
            'SKIPPED' { $stats.Skipped++ }
            'ERROR'   { $stats.Errors++ }
        }
    }
}

# --- PHASE 2: SITE LAUNCH ---
if ($null -ne $TargetSitePath -and -not $DryRun) {
    if (-not $Global:SentinelSiteLaunched) {
        AutoStartWebSite -Path $TargetSitePath
        $Global:SentinelSiteLaunched = $true
    }
}

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

Stop-Transcript