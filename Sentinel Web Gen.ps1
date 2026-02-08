# ==============================================================================
# Sentinel Web Gen v17.7 [THE GEEK MODULAR - MULTI-SITE UPDATE]
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

$ConfigFilePath = Join-Path $PSScriptRoot 'config2.0.yml'
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
# --- MAIN PROCESS LOOP (Updated) ---
foreach ($loc in $WebLocations) {
    if ($loc.Role -ne 'Hybrid_Archive' -and $loc.Name -ne 'Photography_Portfolio') { continue }

    Write-Host "`n>>> Syncing: $($loc.Name) Source -> Unified Website" -ForegroundColor White

    # 1. Path Logic: Map to subfolders like docs\recipes, docs\shop, or docs\gallery
    $SubDir = if ($loc.WebSubFolder) { $loc.WebSubFolder } else { 'recipes' }
    $WebDocsRoot = Join-Path $loc.SitePath "docs\$SubDir"

    if (-not (Test-Path $WebDocsRoot)) {
        New-Item -Path $WebDocsRoot -ItemType Directory -Force | Out-Null
    }

    # 2. Cleaning Phase (With Manual Safety preserved)
    if ($loc.PurgeOrphan -and $false) {
        Write-Host "  $($Global:Icons.Broom) Purging $SubDir web docs..." -ForegroundColor Cyan
        if (Test-Path $WebDocsRoot) {
            Get-ChildItem $WebDocsRoot -Exclude '_category_.yml' -Recurse | Remove-Item -Force -Recurse
        }
    }

    # 2. CATEGORY MAPPING
    Write-Host "  $($Global:Icons.Arrow) Mapping categories..." -ForegroundColor Gray
    $SourceFolders = Get-ChildItem -Path $loc.Path -Directory -Recurse -ErrorAction SilentlyContinue
    $stats = [PSCustomObject]@{ Scanned=0; Created=0; Skipped=0 }

    foreach ($dir in $SourceFolders) {
        $stats.Scanned++
        $RelPath = $dir.FullName.Replace($loc.Path, "").TrimStart('\')
        $TargetWebDir = Join-Path $WebDocsRoot $RelPath
        $CategoryFile = Join-Path $TargetWebDir "_category_.yml"

        $ProgressMsg = "`r  $($Global:Icons.Check) [INDEXING] [$($stats.Scanned)/$($SourceFolders.Count)] $RelPath"
        Write-Host $ProgressMsg.PadRight($SafeWidth) -NoNewline -ForegroundColor Gray

        if (-not (Test-Path $CategoryFile)) {
            Write-SentinelCategoryYaml -FolderPath $TargetWebDir -FolderName $dir.Name -Force $false
            $stats.Created++
        } else {
            $stats.Skipped++
        }
    }

    Write-Host ""
    Write-Host "  $($Global:Icons.Check) Indexing Complete: $($stats.Created) Created, $($stats.Skipped) Skipped." -ForegroundColor Green

    # 2.5 Master Index
    $MasterIndexPath = Join-Path $WebDocsRoot "index.md"
    if (-not (Test-Path $MasterIndexPath)) {
        Write-Host "  $($Global:Icons.Check) Creating Master Index..." -ForegroundColor Green
        Write-SentinelRecipeIndex -TargetRoot $WebDocsRoot -GroupCount $SourceFolders.Count
    } else {
        Write-Host "  $($Global:Icons.Check) Master Index exists. Skipping write." -ForegroundColor Gray
    }

    # 3. GROUPING & IMPORTING
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

    $stats = [PSCustomObject]@{ Scanned=0; Created=0; Skipped=0; Errors=0 }
    $ProcessTag = if ($loc.Template -eq 'recipe-card') { 'RECIPE' } else { 'GROUP ' }

    foreach ($group in $FileGroups) {
        $RelPath = $group.Group[0].DirectoryName.Replace($loc.Path, "").TrimStart('\')
        $TargetWebDir = Join-Path $WebDocsRoot $RelPath
        $TargetFile = Join-Path $TargetWebDir "$($group.Name).md"
        $stats.Scanned += $group.Count

        $CurrentCount = $stats.Created + $stats.Skipped + $stats.Errors + 1
        $LiveStats = "$($stats.Created) Created | $($stats.Skipped) Preserved"
        $GroupMsg = "`r  $($Global:Icons.Arrow) [$ProcessTag] [$($CurrentCount.ToString().PadLeft($($FileGroups.Count.ToString().Length)))/$($FileGroups.Count)] $LiveStats"
        Write-Host $GroupMsg.PadRight($SafeWidth) -NoNewline -ForegroundColor Cyan

        if (-not (Test-Path $TargetFile)) {
            $Result = Build-WebPageFromTemplate -SourceFiles $group.Group -TargetFolder $TargetWebDir -TemplateType $loc.Template -Overwrite $false
            if ($Result -eq 'CREATED') { $stats.Created++ } else { $stats.Errors++ }
        } else {
            $stats.Skipped++
        }
    }

    $FinalMsg = "`r  $($Global:Icons.Check) [$ProcessTag] [$($FileGroups.Count)/$($FileGroups.Count)] $($stats.Created) Created | $($stats.Skipped) Preserved"
    Write-Host $FinalMsg.PadRight($SafeWidth) -ForegroundColor Green

    # 4. STATUS CHECK (Quick Ping)
    try {
        $TCP = New-Object System.Net.Sockets.TcpClient
        # Note: Docusaurus usually increments ports (3000, 3001, 3002) if multiple run.
        # This check is a quick 'Is anything there?' ping.
        if ($TCP.BeginConnect("localhost", 3000, $null, $null).AsyncWaitHandle.WaitOne(100)) {
            $StatusText = "ONLINE"
        } else {
            $StatusText = "OFFLINE"
        }
        $TCP.Close()
    } catch {
        $StatusText = "OFFLINE"
    }

    # 5. REPORTING
    $Summary = @"
Sentinel Sync: $($loc.Name)
---------------------------------------
Current Site Status:  $StatusText
Total Groups:         $($FileGroups.Count)
NEW Pages Created:    $($stats.Created)
EXISTING (Preserved): $($stats.Skipped)
---------------------------------------
Mirror Target:        $WebDocsRoot
"@
    Send-SentinelReport -ReportBody $Summary -JobName $loc.Name -SiteUrl $loc.SiteUrl
}
# --- PHASE 6: FINAL LAUNCH (Unified) ---
Write-Host "`nPHASE 6: Spawning Unified Website..." -ForegroundColor White

# Launch the master site at port 3000
$MasterSite = $WebLocations | Where-Object { $_.SitePath -like '*website*' } | Select-Object -First 1
if ($MasterSite -and -not $YamlData.Settings.DryRun) {
    # This calls the function in Sentinel-Core to npx create or npm start
    AutoStartWebSite -Path $MasterSite.SitePath
}

Write-Host "`nMISSION COMPLETE. Duration: $($globalStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green
Stop-Transcript