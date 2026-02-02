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
$WebLocations = $YamlData.Locations # Ensure this is mapped from your YAML

# Logging Setup
$LogDir = Join-Path $PSScriptRoot ($YamlData.Settings.LogPath)
$LogFile = Join-Path $LogDir 'Sentinel_Web_Gen.log'
if (-not (Test-Path $LogDir)) { Safe-NewItem $LogDir -ItemType Directory -Force | Out-Null }

Start-Transcript -Path $LogFile -Append
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$SafeWidth = $Host.UI.RawUI.WindowSize.Width - 1

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
    if ($loc.PurgeOrphan -and $EffectiveOverwrite) {
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
    Write-Host "  >> Mapping categories..." -ForegroundColor Gray
    $SourceFolders = Get-ChildItem -Path $loc.Path -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $P = $_.FullName
        $Exclude = $false
        foreach ($ex in $YamlData.Exclusions) { if ($P -like "*\$ex*") { $Exclude = $true; break } }
        -not $Exclude
    }

    $idx = 0
    foreach ($dir in $SourceFolders) {
        $idx++
        $RelPath = $dir.FullName.Replace($loc.Path, "").TrimStart('\')
        $TargetWebDir = Join-Path $WebDocsRoot $RelPath
        Write-SentinelCategoryYaml -FolderPath $TargetWebDir -FolderName $dir.Name -Force $EffectiveOverwrite
        Write-Host ("`r  $($Global:Icons.Check) [INDEX] [$idx/$($SourceFolders.Count)] $RelPath").PadRight($SafeWidth) -NoNewline -ForegroundColor Green
        # 2.5 Generate the Master Index
        Write-Host "  $($Global:Icons.Check) Generating Master Index..." -ForegroundColor Green
        Write-SentinelRecipeIndex -TargetRoot $WebDocsRoot -GroupCount $SourceFolders.Count

    }
    Write-Host ""

    # 3. GROUPING & IMPORTING

    # GEEK FIX: Dynamically build the allowed extensions list from YAML
    $AllowedExts = @()
    foreach ($Category in $YamlData.FileTypes.Recipes) {
        if ($YamlData.FileTypes.ContainsKey($Category)) {
            $AllowedExts += $YamlData.FileTypes.$Category
        } else {
            $AllowedExts += $Category # Catch direct extensions like '.mp4'
        }
    }

    $AllFiles = Get-ChildItem -Path $loc.Path -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $Ext = $_.Extension.ToLower()
        # Only include files in our dynamic allowed list, excluding junk
        ($Ext -in $AllowedExts) -and -not ($_.FullName -like "*_putaway*")
    }

    $GroupSeparator = if ($loc.GroupSeparator) { $loc.GroupSeparator } else { '-.-' }

    # Improved Grouping: Handles 'natural-body-wash-.-99' vs 'natural-body-wash'
    $FileGroups = $AllFiles | Group-Object {
        $BN = $_.BaseName
        if ($BN -match [regex]::Escape($GroupSeparator)) {
            $BN.Substring(0, $BN.LastIndexOf($GroupSeparator))
        } else { $BN }
    }

    $stats = [PSCustomObject]@{ Scanned=0; Created=0; Updated=0; Errors=0 }

    foreach ($group in $FileGroups) {
        $RelPath = $group.Group[0].DirectoryName.Replace($loc.Path, "").TrimStart('\')
        $TargetWebDir = Join-Path $WebDocsRoot $RelPath
        $stats.Scanned += $group.Count

        $CurrentCount = $stats.Created + $stats.Updated + $stats.Errors + 1
        Write-Host ("`r  $($Global:Icons.Arrow) [GROUP] [$CurrentCount/$($FileGroups.Count)] [$RelPath] | $($group.Name)").PadRight($SafeWidth) -NoNewline -ForegroundColor Cyan

        $Result = Build-WebPageFromTemplate -SourceFiles $group.Group -TargetFolder $TargetWebDir -TemplateType $loc.Template -Overwrite $EffectiveOverwrite
        switch($Result) { 'CREATED' {$stats.Created++} 'UPDATED' {$stats.Updated++} default {$stats.Errors++} }
    }
    Write-Host ""

    # 4. STATUS CHECK (Quick Ping)
    try {
        $TCP = New-Object System.Net.Sockets.TcpClient
        if ($TCP.BeginConnect("localhost", 3000, $null, $null).AsyncWaitHandle.WaitOne(100)) { $StatusText = "ONLINE" } else { $StatusText = "OFFLINE" }
        $TCP.Close()
    } catch { $StatusText = "OFFLINE" }

    # 5. REPORTING (Inside the loop)
    $Summary = @"
Sentinel Sync: $($loc.Name)
---------------------------------------
Deep Clean Performed: $WasDeepCleaned
Current Site Status:  $StatusText
---------------------------------------
Grouped Pages:        $($FileGroups.Count)
Individual Files:     $($stats.Scanned)
New Pages Created:    $($stats.Created)
Pages Updated:        $($stats.Updated)
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