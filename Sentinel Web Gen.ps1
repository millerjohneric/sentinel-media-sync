# ==============================================================================
# Sentinel Web Gen v20.28 [PHASE 0 REPORTER & ODOMETER RESTORED]
# ==============================================================================

# --- BOOTSTRAP LIBRARY ---
$CorePath = Join-Path $PSScriptRoot "Sentinel-Core.ps1"
if (Test-Path $CorePath) {
    . $CorePath
    Write-Host "  $($Global:Icons.Check) Core Library Loaded." -ForegroundColor Gray
} else {
    Write-Error "CRITICAL: Sentinel-Core.ps1 not found."
    exit
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Stats = @{ Scanned = 0; Created = 0; Updated = 0; Skipped = 0; Errors = 0 }

# --- PHASE 0: RAW-SCAN & REPORT ---
Write-Host "PHASE 0: Scanning Configuration..." -ForegroundColor Cyan

$ConfigPath = Join-Path $PSScriptRoot 'Sentinel-Config.yml'
$YamlData = Get-Content $ConfigPath -Raw | ConvertFrom-Yaml
$Locs = if ($YamlData.Locations) { $YamlData.Locations } else { $YamlData.locations }

# Identify the Website Root Path
$TargetWebsitePath = $null
foreach ($loc in $Locs) {
    if ($loc.RootType -eq 'web-root') {
        $TargetWebsitePath = $loc.SitePath.ToString().Replace("'", "").Trim()
        break
    }
}

# Change this line in Sentinel Web Gen.ps1:
Write-SentinelPhase0 -YamlData $YamlData -TargetWebsitePath $TargetWebsitePath

# --- PHASE 1: ENGINE PREP ---
if ($YamlData.Settings.PurgeWebsite -eq $true) {
    Write-Host "`n  $($Global:Icons.Warning) PurgeWebsite is TRUE: Wiping engine..." -ForegroundColor Yellow
    
    # SAFETY CHECK: Step back if terminal is inside the target folder
    $CurrentPath = (Get-Location).Path
    if ($CurrentPath -like "$TargetWebsitePath*") {
        Write-Host "  $($Global:Icons.Arrow) Terminal detected inside target. Stepping back to parent..." -ForegroundColor Gray
        Set-Location (Split-Path $TargetWebsitePath -Parent)
    }

    if (Test-Path $TargetWebsitePath) {
        # Stop node to release file locks
        Stop-Process -Name "node" -ErrorAction SilentlyContinue
        
        Write-Host "  $($Global:Icons.Arrow) Removing: $TargetWebsitePath" -ForegroundColor Gray
        Remove-Item $TargetWebsitePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (!(Test-Path $TargetWebsitePath)) {
    Write-Host "  $($Global:Icons.Warning) Engine missing. Scaffolding Docusaurus..." -ForegroundColor Yellow
    $ParentDir = Split-Path $TargetWebsitePath
    New-Item $ParentDir -ItemType Directory -Force | Out-Null
    Set-Location $ParentDir
    cmd /c "echo y | npx create-docusaurus@latest website classic --javascript --skip-install"
    Set-Location $TargetWebsitePath
    npm install
}

Remove-SentinelBoilerplate -SitePath $TargetWebsitePath

# --- PHASE 2: CONTENT SEEDING & LIVE ODOMETER ---
Write-Host "`nPHASE 2: Populating Content & Generating Pages..." -ForegroundColor Cyan

Initialize-SentinelTemplates -TemplateDir $YamlData.Settings.TemplateDir
Invoke-SentinelBranding -SitePath $TargetWebsitePath -TemplateDir $YamlData.Settings.TemplateDir

$WebLocs = $Locs | Where-Object { $null -ne $_.WebSubFolder }

foreach ($loc in $WebLocs) {
    $Stats.Scanned++
    $SubFolder = $loc.WebSubFolder.ToString().Replace("'", "")
    $TargetDir = Join-Path $TargetWebsitePath $SubFolder
    
    if (!(Test-Path $TargetDir)) { New-Item $TargetDir -ItemType Directory -Force | Out-Null }

    # Update Odometer for the current location
    Write-SentinelOdometer -Tag 'GEN' -Source $loc.Name -Path $SubFolder -Current $Stats.Scanned -Total $WebLocs.Count -Time $globalStopwatch.Elapsed.ToString("mm\:ss")

    # DYNAMIC TEMPLATE MATCHING
    if ($null -ne $loc.Template) {
        $MediaSource = $loc.Path.ToString().Replace("'", "")
        $TemplateName = $loc.Template.ToString().Replace("'", "")
        
        # Map Template Names to sub-folders found in S:\...\content-seeds
        $TemplateRelPath = switch ($TemplateName) {
            'recipe-card'   { "recipes\recipe-card.md" }
            'masonry-grid'  { "gallery\masonry-grid.md" }
            'hand-crafted'  { "shop\hand-crafted.md" }
            'intro - docs'  { "docs\intro - docs.md" }
            Default         { "$TemplateName.md" }
        }

        $TemplatePath = Join-Path $YamlData.Settings.TemplateDir "content-seeds\$TemplateRelPath"
        
        if (Test-Path $MediaSource) {
            if (Test-Path $TemplatePath) {
                # Approved Verb: Invoke-
                Invoke-SentinelRecipeContent -SourceDataDir $MediaSource -TargetDir $TargetDir -TemplatePath $TemplatePath
                
                # Copy assets (images/videos) alongside generated markdown
                robocopy $MediaSource $TargetDir /E /R:0 /W:0 /NJH /NJS /NDL /NFL /NC /NS /NP
                $Stats.Created++
            } else {
                Write-Host "  $($Global:Icons.Error) Template missing: $TemplatePath" -ForegroundColor Red
                $Stats.Errors++
            }
        } else {
            Write-Host "  $($Global:Icons.Error) Media Source missing: $MediaSource" -ForegroundColor Red
            $Stats.Errors++
        }
    }
    # Handling standard website mirroring (locations without specific templates)
    elseif ($loc.Role -eq 'Website' -and $SubFolder -ne 'docs') {
        $Source = if ($loc.Path) { $loc.Path.ToString().Replace("'", "") } else { $null }
        if ($null -ne $Source -and (Test-Path $Source)) {
            # Use /MIR for standard websites to keep them identical to source
            robocopy $Source $TargetDir /MIR /R:0 /W:0 /NJH /NJS /NDL /NFL /NC /NS /NP
            $Stats.Updated++
        }
    }

    # Final Odometer update for this loop iteration
    Write-SentinelOdometer -Tag 'GEN' -Source $loc.Name -Path $SubFolder -Current $Stats.Scanned -Total $WebLocs.Count -Time $globalStopwatch.Elapsed.ToString("mm\:ss")
}
Clear-SentinelOdometer

# NEW: Add a small delay to ensure the file system handles the robocopy/write operations
Start-Sleep -Seconds 2 

# --- PHASE 3: FINALIZING CONFIGS & REGISTRY ---
Write-Host "`nPHASE 3: Patching Dynamic Configs..." -ForegroundColor Cyan

$RegPath = Join-Path $YamlData.Settings.TemplateDir "core-config/nav-registry.json"
if (Test-Path $RegPath) {
    # Using -Raw to ensure we get a clean string for conversion
    $Reg = Get-Content $RegPath -Raw | ConvertFrom-Json
    
    # Use Add-Member to force these properties into existence
    $Reg | Add-Member -MemberType NoteProperty -Name 'lastUpdate' -Value (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
    $Reg | Add-Member -MemberType NoteProperty -Name 'version' -Value '20.28' -Force

    $Reg | ConvertTo-Json | Out-File $RegPath -Encoding UTF8 -Force
    Write-Host "  $($Global:Icons.Check) Registry Updated: $($Reg.lastUpdate)" -ForegroundColor Gray
}

# ADDED: Settle time for the file system before Sidebar generation
Start-Sleep -Seconds 2

Write-SentinelDocusaurusConfig -SitePath $TargetWebsitePath -Locations $Locs
Write-SentinelSidebars -SitePath $TargetWebsitePath -Locations $Locs

# FINAL STEP: Check if index.md exists in core folders, if not, copy seed
foreach ($loc in $Locs) {
    if ($loc.Role -eq 'Website' -and $loc.WebSubFolder) {
        $TargetIdx = Join-Path $TargetWebsitePath "$($loc.WebSubFolder)\index.md"
        if (!(Test-Path $TargetIdx)) {
             Write-Host "  $($Global:Icons.Warning) Missing index for $($loc.Name), creating placeholder..." -ForegroundColor Yellow
             Write-SentinelRecipeIndex -TargetRoot (Split-Path $TargetIdx) -GroupCount 0
        }
    }
}

# --- PHASE 4: MISSION REPORT & LAUNCH ---
Write-Host "`nPHASE 4: Finalizing & Handing off to Node..." -ForegroundColor Cyan

if ($YamlData.Settings.EmailSettings.Enabled) {
    Send-SentinelNotification -Stats $Stats -Duration $globalStopwatch.Elapsed -JobName "Sentinel Web Gen v20.28"
    Write-Host "  $($Global:Icons.Check) Mission Report Emailed." -ForegroundColor Gray
}

Start-SentinelWebsite -Path $TargetWebsitePath

$globalStopwatch.Stop()
Write-Host "`nMISSION COMPLETE. Site is LIVE." -ForegroundColor Green
Set-Location ..
Start-Sleep -Seconds 5
Exit