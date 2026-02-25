# ==============================================================================
# Sentinel Sync v20.9 [STABLE]
# ==============================================================================
# --- BOOTSTRAP ---
. (Join-Path $PSScriptRoot "Sentinel-Core.ps1")
$ConfigPath = Join-Path $PSScriptRoot 'Sentinel-Config.yml'

# Force Global scope to resolve "Variable not defined" errors in Core functions
$Global:YamlData = Get-Content $ConfigPath -Raw | ConvertFrom-Yaml
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# --- PATH MAPPING ---
$Engine = $Global:YamlData.Locations | Where-Object { $_.RootType -eq 'web-root' }
$TargetWebsitePath = $Engine.SitePath
$BuildPath = $Engine.Path
$Settings = $Global:YamlData.Settings

# --- REVISION TRACKER ---
$CurrentRevision = Get-SentinelRevision -ScriptPath $PSScriptRoot
$ToolHeader = "Sentinel Unified Sync & Gen $CurrentRevision"

Clear-Host
Write-Host "==============================================================================" -ForegroundColor Gray
Write-Host "# $ToolHeader" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Gray

# --- PHASE 0: INITIALIZATION ---
Write-SentinelPhase0 -YamlData $Global:YamlData

Initialize-SentinelSecrets
Initialize-SentinelTemplates -TemplateDir $Engine.TemplateDir
Initialize-SentinelWebRoot -BuildPath $BuildPath -DeployPath $TargetWebsitePath -EngineLoc $Engine
Write-SentinelHomepageRedirect -SitePath $TargetWebsitePath

# INVISIBLE SILENT INTERRUPT WINDOW (5 Seconds)
$Timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($Timer.Elapsed.TotalSeconds -lt 5) {
    if ([System.Console]::KeyAvailable) { 
        $null = [System.Console]::ReadKey($true) 
        break 
    }
    Start-Sleep -Milliseconds 100 
}
$Timer.Stop()

# --- PHASE 1: MIRRORING ---
Write-Host "`nPHASE 1: Mirroring Content (Silent Interrupt Active)..." -ForegroundColor Cyan
$MediaStats = Sync-SentinelMedia -Locations $Global:YamlData.Locations -Settings $Settings
if ($null -eq $MediaStats) {
    $MediaStats = @{ 'Scanned' = 0; 'Moved' = 0; 'Errors' = 1 }
}

# --- PHASE 2: GENERATION ---
Write-Host "`nPHASE 2: Generating Website Content..." -ForegroundColor Cyan
$WebLocs = $YamlData.Locations | Where-Object { $_.Role -eq 'Website' }

foreach ($loc in $WebLocs) {
    if ($loc.WebSubFolder -eq 'docs') { continue }
    
    # This now dynamically finds Sync-SentinelRecipes and passes the C:\... paths
    Invoke-SentinelWebPipeline -loc $loc -Settings $Settings -TargetWebsitePath $TargetWebsitePath
}

# --- CRITICAL: SIDEBAR CRASH FIX ---
# Docusaurus requires an 'index.md' or 'intro.md' to build the sidebar correctly
$IndexFile = Join-Path $TargetWebsitePath "docs\index.md"
if (!(Test-Path $IndexFile)) {
    '@latest' | Out-File -FilePath $IndexFile -Encoding utf8
    '# Welcome to Source Studio' | Out-File -FilePath $IndexFile -Append -Encoding utf8
}
# --- PHASE 3: FINALIZATION ---
Write-Host "`nPHASE 3: Finalizing Studio Framework..." -ForegroundColor Cyan

# Remove Docusaurus templates, update config, and build sidebars
Invoke-SentinelBranding -SitePath $TargetWebsitePath -TemplateDir $TemplateDir
Write-SentinelDocusaurusConfig -SitePath $TargetWebsitePath -YamlData $YamlData
Write-SentinelSidebars -SitePath $TargetWebsitePath
Write-SentinelXmlTree -SitePath $TargetWebsitePath
# --- PHASE 4: ENGINE LAUNCH ---
# Launches in a separate window listening on all ports for ASUS DDNS
Start-SentinelProduction -SitePath $TargetWebsitePath

# --- PHASE 5: MISSION REPORT ---
$globalStopwatch.Stop()
$Duration = $globalStopwatch.Elapsed.ToString('mm\:ss')

if ($MediaStats.Errors -gt 0) { $ErrorColor = 'Red' } else { $ErrorColor = 'Gray' }

Write-Host "`n==============================================================================" -ForegroundColor Gray
Write-Host " MISSION COMPLETE: $ToolHeader" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Gray
Write-Host "  $($Global:Icons.Check) Files Scanned: $($MediaStats.Scanned)" -ForegroundColor Gray
Write-Host "  $($Global:Icons.Arrow) Files Moved:   $($MediaStats.Moved)"   -ForegroundColor Cyan
Write-Host "  $($Global:Icons.Error) Errors:        $($MediaStats.Errors)"  -ForegroundColor $ErrorColor
Write-Host "  $($Global:Icons.Check) Total Time:    $Duration"               -ForegroundColor White
Write-Host "  $($Global:Icons.Check) Remote Access: http://millerjohneric.asuscomm.com:3000" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Gray

if ($YamlData.Settings.EmailSettings.Enabled) {
    Send-SentinelNotification `
        -SiteName 'Source Studio' `
        -Status 'Online' `
        -TotalGroups ($YamlData.Locations | Measure-Object).Count `
        -NewPages $MediaStats.Moved `
        -Preserved ($MediaStats.Scanned - $MediaStats.Moved) `
        -MirrorTarget $TargetWebsitePath `
        -SiteUrl 'http://millerjohneric.asuscomm.com:3000'
}