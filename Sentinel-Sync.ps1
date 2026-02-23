# ==============================================================================
# Sentinel Sync v20.9 [STABLE]
# ==============================================================================

# --- BOOTSTRAP ---
. (Join-Path $PSScriptRoot "Sentinel-Core.ps1")
$ConfigPath = Join-Path $PSScriptRoot 'Sentinel-Config.yml'
$YamlData = Get-Content $ConfigPath -Raw | ConvertFrom-Yaml
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# PATH MAPPING
$Settings = $YamlData.Settings
$TargetWebsitePath = $Settings.SitePath
$SourceFramework = 'C:\Source\GEEK\Sentinel\website'
$TemplateDir = $Settings.TemplateDir

# REVISION TRACKER
$CurrentRevision = Get-SentinelRevision -ScriptPath $PSScriptRoot
$ToolHeader = "Sentinel Unified Sync & Gen $CurrentRevision"

# --- PHASE 0 & 1 ---
Clear-Host
Write-Host "==============================================================================" -ForegroundColor Gray
Write-Host "# $ToolHeader" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Gray
# Phase 0 calculates column widths at runtime based on your YAML
Write-SentinelPhase0 -YamlData $YamlData
# Phase 1 physically moves files and returns stats for the Mission Report
$MediaStats = Sync-SentinelMedia -Locations $YamlData.Locations -Settings $Settings
Write-Host ""

# --- PHASE 2 ---
Write-Host "`nPHASE 2: Generating Website Content..." -ForegroundColor Cyan
$WebLocs = $YamlData.Locations | Where-Object { $null -ne $_.WebSubFolder }
$current = 0

foreach ($loc in $WebLocs) {
    $current++
    $SubFolder = $loc.WebSubFolder.ToString().Trim().Replace("'", "")
    Write-SentinelOdometer -Tag 'GEN' -Source $loc.Name -Path $SubFolder -Current $current -Total $WebLocs.Count -Time $globalStopwatch.Elapsed.ToString("mm\:ss")
    Invoke-SentinelWebPipeline -loc $loc -Settings $Settings -TargetWebsitePath $TargetWebsitePath
}

# --- PHASE 3: STUDIO DEPLOYMENT ---
Write-Host "`nPHASE 3: Mirroring Framework to Source Studio..." -ForegroundColor Cyan

# 1. Resolve Path and Initialize/Purge
$TargetWebsitePath = [string]$YamlData.Settings.SitePath
Initialize-SentinelWebRoot -RootPath $TargetWebsitePath -Settings $YamlData.Settings

# 2. Seed Engine (The rest of your existing Phase 3 logic)
$EngineDocsDir = Join-Path $TargetWebsitePath "docs"
if (!(Test-Path $EngineDocsDir)) { New-Item $EngineDocsDir -ItemType Directory -Force | Out-Null }

# 3. DYNAMIC SEEDING: Iterate through all 'Website' roles
Write-Host "  $($Global:Icons.Check) Seeding engine from YAML sources..." -ForegroundColor Gray

# Ensure the engine docs directory is ready
if (!(Test-Path $EngineDocsDir)) { New-Item $EngineDocsDir -ItemType Directory -Force | Out-Null }

foreach ($loc in $YamlData.Locations) {
    if ($loc.Role -ne 'Website') { continue }
    
    $Source = $loc.Path
    $SubFolder = $loc.WebSubFolder
    $Destination = Join-Path $TargetWebsitePath $SubFolder
    
    Write-Host "    $($Global:Icons.Arrow) Pulling content: $($loc.Name) -> $SubFolder" -ForegroundColor Gray
    
    # Robocopy logic
    robocopy $Source $Destination /MIR /R:0 /W:0 /NDL /NFL /NJH /NJS
}

# 4. Inject Branding & Configs
Invoke-SentinelBranding -SitePath $TargetWebsitePath -TemplateDir $TemplateDir
Write-SentinelDocusaurusConfig -SitePath $TargetWebsitePath -Locations $YamlData.Locations
Write-SentinelSidebars -SitePath $TargetWebsitePath -Locations $YamlData.Locations

# --- PHASE 4: ENGINE LAUNCH ---
Write-Host "`nPHASE 4: Launching Source Studio Engine..." -ForegroundColor Cyan

Push-Location $TargetWebsitePath
try {
    # Only run install if node_modules is missing
    if (!(Test-Path "node_modules")) {
        Write-Host "  $($Global:Icons.Info) Initializing Node Modules..." -ForegroundColor Gray
        npm install
    }
    npm start
} finally {
    Pop-Location
}

# --- PHASE 5: MISSION REPORT ---
$globalStopwatch.Stop()
$Duration = $globalStopwatch.Elapsed.ToString('mm\:ss')

# Standard PowerShell if/else to avoid the ternary operator error
if ($MediaStats.Errors -gt 0) { $ErrorColor = "Red" } else { $ErrorColor = "Gray" }

Write-Host "`n==============================================================================" -ForegroundColor Gray
Write-Host " MISSION COMPLETE: $ToolHeader" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Gray
Write-Host "  $($Global:Icons.Check) Files Scanned: $($MediaStats.Scanned)" -ForegroundColor Gray
Write-Host "  $($Global:Icons.Arrow) Files Moved:   $($MediaStats.Moved)"   -ForegroundColor Cyan
Write-Host "  $($Global:Icons.Error) Errors:        $($MediaStats.Errors)"  -ForegroundColor $ErrorColor
Write-Host "  $($Global:Icons.Check) Total Time:    $Duration"               -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor Gray

# If you still have the notification function in Core, trigger it here
if ($YamlData.Settings.EmailSettings.Enabled) {
    Send-SentinelNotification -Stats $MediaStats -Duration $Duration -JobName 'UnifiedSync'
}