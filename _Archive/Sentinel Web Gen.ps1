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
foreach ($loc in $WebLocs) {
    $Stats.Scanned++
    $SubFolder = $loc.WebSubFolder.ToString().Replace("'", "")
    $TargetDir = Join-Path $YamlData.Settings.SitePath $SubFolder
    
    # RESTORE THE ODOMETER CALL HERE
    Write-SentinelOdometer -Tag 'GEN' -Source $loc.Name -Path $SubFolder -Current $Stats.Scanned -Total $WebLocs.Count -Time $globalStopwatch.Elapsed.ToString("mm\:ss")
    
    if ($null -ne $loc.Template) {
        $TemplateRaw = $loc.Template.ToString().Replace("'", "")
        
        if ($TemplateRaw -match '^\[(.+)\](.+)$') {
            $Category = $Matches[1].ToLower()
            $TName = $Matches[2].Replace(".md", "") # Strips .md if present
            $RelPath = "content-seeds\$Category\$TName.md"
        } else {
            $RelPath = $TemplateRaw.TrimStart('\')
        }

        $TemplatePath = Join-Path $YamlData.Settings.TemplateDir $RelPath
        
        if (Test-Path $TemplatePath) {
            $MediaSource = $loc.Path.ToString().Replace("'", "")
            $Files = Get-ChildItem $MediaSource -File | Where-Object { $_.Name -ne 'index.md' }
            $Separator = if ($loc.GroupSeparator) { $loc.GroupSeparator } else { '-.-' }
            
            # Calculate groups for the Mission Report
            $SiteGroups = ($Files | Group-Object { if ($_.Name -contains $Separator) { $_.BaseName.Split($Separator)[0] } else { $_.BaseName } }).Count
            
            Invoke-SentinelRecipeContent -SourceDataDir $loc.Path -TargetDir $TargetDir -TemplatePath $TemplatePath -GroupSeparator $Separator
            
            # Update individual site reports
            if ($YamlData.Settings.EmailSettings.Enabled) {
                $CurrentStatus = if (Get-Process -Name "node" -ErrorAction SilentlyContinue) { "ONLINE" } else { "OFFLINE" }
                Send-SentinelNotification `
                    -SiteName $loc.Name `
                    -Status $CurrentStatus `
                    -TotalGroups $SiteGroups `
                    -NewPages $SiteGroups `
                    -Preserved 0 `
                    -MirrorTarget $TargetDir `
                    -SiteUrl "$($YamlData.Settings.SiteUrl)/$SubFolder"
            }
        }
    }
}
Clear-SentinelOdometer

# NEW: Add a small delay to ensure the file system handles the robocopy/write operations
Start-Sleep -Seconds 2 
# --- PHASE 3: FINALIZING CONFIGS & REGISTRY ---
Write-Host "`nPHASE 3: Patching Dynamic Configs..." -ForegroundColor Cyan

$RegPath = Join-Path $YamlData.Settings.TemplateDir "core-config/nav-registry.json"
if (Test-Path $RegPath) {
    $Reg = Get-Content $RegPath -Raw | ConvertFrom-Json
    $Reg | Add-Member -MemberType NoteProperty -Name 'lastUpdate' -Value (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
    $Reg | Add-Member -MemberType NoteProperty -Name 'version' -Value '20.28' -Force
    $Reg | ConvertTo-Json | Out-File $RegPath -Encoding UTF8 -Force
    Write-Host "  $($Global:Icons.Check) Registry Updated: $($Reg.lastUpdate)" -ForegroundColor Gray
}
# --- PHASE 3: CONFIGURATION & SIDEBARS ---
Write-Host "`nPHASE 3: Generating Navigation & Sidebars..." -ForegroundColor Cyan

foreach ($loc in $Locs) {
    if ($loc.Role -eq 'Website' -and $loc.WebSubFolder) {
        $TargetPath = Join-Path $TargetWebsitePath $loc.WebSubFolder
        
        if (Test-Path $TargetPath) {
            Write-Host "  $($Global:Icons.Arrow) Scanning nested structure for $($loc.Name)..." -ForegroundColor Gray
            
            # Recursive scan: Find EVERY subfolder and create a _category_.yml
            $SubDirs = Get-ChildItem $TargetPath -Recurse | Where-Object { $_.PSIsContainer }
            foreach ($dir in $SubDirs) {
                $CleanLabel = (Get-Culture).TextInfo.ToTitleCase($dir.Name.Replace("-", " "))
                Write-SentinelCategoryYaml -Path $dir.FullName -Label $CleanLabel
            }
        }
    }
}

# Settle time for file system
Start-Sleep -Seconds 2

# Final generation of JS configs
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
# --- PHASE 4: FINALIZING & LAUNCH ---
Write-Host "`nPHASE 4: Finalizing & Handing off to Node..." -ForegroundColor Cyan
Start-SentinelWebsite -Path $TargetWebsitePath

Start-SentinelWebsite -Path $TargetWebsitePath

$globalStopwatch.Stop()
Write-Host "`nMISSION COMPLETE. Site is LIVE." -ForegroundColor Green
Set-Location ..
Start-Sleep -Seconds 5
Exit