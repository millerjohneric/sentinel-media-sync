# ==============================================================================
# Sentinel Web Gen v17.7 [THE GEEK MODULAR - FINALIZED]
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# 1. Import Core
$CorePath = Join-Path $PSScriptRoot 'Sentinel-Core.ps1'
if (Test-Path $CorePath) { . $CorePath } else { Write-Error "CRITICAL: Sentinel-Core.ps1 not found!"; exit }

# 2. Initialization & Config
Set-Location -Path $PSScriptRoot
if (-not (Get-Module -ListAvailable powershell-yaml)) { Install-Module -Name powershell-yaml -Scope CurrentUser -Force }
Import-Module powershell-yaml

$ConfigFilePath = Join-Path $PSScriptRoot 'config.yml'
$YamlData = Get-Content $ConfigFilePath -Raw | ConvertFrom-Yaml
$WebLocations = $YamlData.Locations

# Logging Setup
$LogDir = Join-Path $PSScriptRoot ($YamlData.Settings.LogPath)
$LogFile = Join-Path $LogDir 'Sentinel_Web_Gen.log'
if (-not (Test-Path $LogDir)) { Safe-NewItem $LogDir -ItemType Directory -Force | Out-Null }

Start-Transcript -Path $LogFile -Append

$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$SafeWidth = Get-SentinelWidth

# --- PHASE 0: MASTER PLAN ---
Write-Host "`nPHASE 0: Web Generation Readiness..." -ForegroundColor White
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))

Write-SentinelPhase0 -Locations $WebLocations -JobType 'Web'

Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))

# --- MAIN PROCESS LOOP ---
foreach ($loc in $WebLocations) {
    if ($loc.Role -ne 'Hybrid_Archive') { continue }

    Write-Host "`n>>> Syncing: $($loc.Name) Source -> Website" -ForegroundColor White
    $EffectiveOverwrite = if ($null -ne $loc.Overwrite) { $loc.Overwrite } else { $true }
    $WebDocsRoot = Join-Path $loc.SitePath "docs\recipes"

    # Track status for reporting
    $WasDeepCleaned = "No"
    $StatusText = "CHECKING..."

    # 1. CLEANING PHASE (NAS-Optimized)
    #                             manual safety change false to true
    if ($loc.PurgeOrphan -and $EffectiveOverwrite -and $false) {
        Write-Host "  $($Global:Icons.Broom) Purging web docs (NAS Mode)..." -ForegroundColor Cyan

        # Kill Docusaurus to release network handles
        Stop-Process -Name node, npm -Force -ErrorAction SilentlyContinue

        if (Test-Path $WebDocsRoot) {
            # DONT delete the root. Delete only the CONTENTS.
            # This preserves the Network Permissions on the 'recipes' folder itself.
            Get-ChildItem $WebDocsRoot -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -Path $WebDocsRoot -ItemType Directory -Force | Out-Null
        }
        $WasDeepCleaned = "Yes"
    }

    # 2. CATEGORY MAPPING
    Write-Host "  $($Global:Icons.Arrow) Mapping categories..." -ForegroundColor Gray

    $stats = [PSCustomObject]@{ Scanned=0; Created=0; Skipped=0 }

    foreach ($dir in $SourceFolders) {
        $stats.Scanned++
        $RelPath = $dir.FullName.Replace($loc.Path, "").TrimStart('\')
        $TargetWebDir = Join-Path $WebDocsRoot $RelPath
        $CategoryFile = Join-Path $TargetWebDir "_category_.yml"

        # LIVE WRITE: Update the same line repeatedly
        $ProgressMsg = "`r  $($Global:Icons.Check) [INDEXING] [$($stats.Scanned)/$($SourceFolders.Count)] $RelPath"
        Write-Host $ProgressMsg.PadRight($SafeWidth) -NoNewline -ForegroundColor Gray

        # STRICT OVERWRITE CHECK
        if (-not (Test-Path $CategoryFile)) {
            Write-SentinelCategoryYaml -FolderPath $TargetWebDir -FolderName $dir.Name -Force $false
            $stats.Created++
        } else {
            $stats.Skipped++
        }
    }

    Write-Host ""
    Write-Host "  $($Global:Icons.Check) Indexing Complete: $($stats.Created) Created, $($stats.Skipped) Skipped." -ForegroundColor Green

    # 2.5 Master Index - Only write if missing
    $MasterIndexPath = Join-Path $WebDocsRoot "index.md"
    if (-not (Test-Path $MasterIndexPath)) {
        Write-Host "  $($Global:Icons.Check) Creating Master Index..." -ForegroundColor Green
        Write-SentinelRecipeIndex -TargetRoot $WebDocsRoot -GroupCount $SourceFolders.Count
    } else {
        Write-Host "  $($Global:Icons.Check) Master Index exists. Skipping write." -ForegroundColor Gray
    }

    # 3. GROUPING & IMPORTING

    # GEEK FIX: Dynamically build the allowed extensions list from YAML
    $AllowedExts = @()
    foreach ($Category in $YamlData.FileTypes.Recipes) {
        if ($YamlData.FileTypes.ContainsKey($Category)) {
            $AllowedExts += $YamlData.FileTypes.$Category
        } else {
            $AllowedExts += $Category
        }
    }

    $AllFiles = Get-ChildItem -Path $loc.Path -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $Ext = $_.Extension.ToLower()
        ($Ext -in $AllowedExts) -and -not ($_.FullName -like "*_putaway*")
    }

    $GroupSeparator = if ($loc.GroupSeparator) { $loc.GroupSeparator } else { '-.-' }

    $FileGroups = $AllFiles | Group-Object {
        $BN = $_.BaseName
        if ($BN -match [regex]::Escape($GroupSeparator)) {
            $BN.Substring(0, $BN.LastIndexOf($GroupSeparator))
        } else { $BN }
    }

    # Ensure Skipped is defined to avoid property-not-found exceptions
    $stats = [PSCustomObject]@{ Scanned=0; Created=0; Skipped=0; Errors=0 }

    # Determine the Tag based on Template from config
    $ProcessTag = if ($loc.Template -eq 'recipe-card') { 'RECIPE' } else { 'GROUP ' }

    foreach ($group in $FileGroups) {
        $RelPath = $group.Group[0].DirectoryName.Replace($loc.Path, "").TrimStart('\')
        $TargetWebDir = Join-Path $WebDocsRoot $RelPath
        $TargetFile = Join-Path $TargetWebDir "$($group.Name).md"
        $stats.Scanned += $group.Count

        # --- THE LIVE ODOMETER ---
        $CurrentCount = $stats.Created + $stats.Skipped + $stats.Errors + 1

        # Construct a clean status string: 0 Created | 466 Preserved
        $LiveStats = "$($stats.Created) Created | $($stats.Skipped) Preserved"

        # Format the line: Arrow -> [TAG] [Count/Total] Stats
        # We remove the trailing filename here to keep the line clean and static
        $GroupMsg = "`r  $($Global:Icons.Arrow) [$ProcessTag] [$($CurrentCount.ToString().PadLeft($($FileGroups.Count.ToString().Length)))/$($FileGroups.Count)] $LiveStats"

        # PadRight ensures that as the numbers shift, any old artifacts are cleared
        Write-Host $GroupMsg.PadRight($SafeWidth) -NoNewline -ForegroundColor Cyan

        # --- LOGIC ---
        if (-not (Test-Path $TargetFile)) {
            $Result = Build-WebPageFromTemplate -SourceFiles $group.Group -TargetFolder $TargetWebDir -TemplateType $loc.Template -Overwrite $false
            if ($Result -eq 'CREATED') { $stats.Created++ } else { $stats.Errors++ }
        } else {
            $stats.Skipped++
        }
    }

    # Final pass to show the absolute final count [466/466]
    $FinalMsg = "`r  $($Global:Icons.Check) [$ProcessTag] [$($FileGroups.Count)/$($FileGroups.Count)] $($stats.Created) Created | $($stats.Skipped) Preserved"
    Write-Host $FinalMsg.PadRight($SafeWidth) -ForegroundColor Green

    # 4. STATUS CHECK (Quick Ping)
    try {
        $TCP = New-Object System.Net.Sockets.TcpClient
        if ($TCP.BeginConnect("localhost", 3000, $null, $null).AsyncWaitHandle.WaitOne(100)) { $StatusText = "ONLINE" } else { $StatusText = "OFFLINE" }
        $TCP.Close()
    } catch { $StatusText = "OFFLINE" }

    # 5. REPORTING
    $Summary = @"
Sentinel Sync: $($loc.Name)
---------------------------------------
Mode:                 OVERWRITE=FALSE
Current Site Status:  $StatusText
---------------------------------------
Total Recipe Groups:  $($FileGroups.Count)
Total Source Files:   $($stats.Scanned)
---------------------------------------
NEW Pages Created:    $($stats.Created)
EXISTING (Preserved): $($stats.Skipped)
Build Errors:         $($stats.Errors)
---------------------------------------
Mirror Target:        $WebDocsRoot
"@

    Send-SentinelReport -ReportBody $Summary -JobName $loc.Name -SiteUrl $loc.SiteUrl
    Write-Host "`nSummary for $($loc.Name):" -ForegroundColor White
    Write-Host $Summary -ForegroundColor Gray
}

# 6. FINAL LAUNCH
$Primary = $WebLocations | Where-Object {$_.Role -eq 'Hybrid_Archive'} | Select -First 1
if ($Primary -and -not $YamlData.Settings.DryRun -and $StatusText -ne "ONLINE") {
    Write-Host "`n  [LAUNCH] Spawning Docusaurus..." -ForegroundColor Green
    $TargetSitePath = $loc.SitePath
    AutoStartWebSite -Path $TargetSitePath
}
Write-Host "`nMISSION COMPLETE. Duration: $($globalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green
Stop-Transcript