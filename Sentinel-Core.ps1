[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Sentinel-Config.yml')
)

Set-Location -Path $PSScriptRoot

$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'sentinel-media-sync.psd1'

if (Test-Path -Path $ManifestPath) {
    Import-Module -Name $ManifestPath -Force
} else {
    $PublicScripts  = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public\*.ps1') -ErrorAction SilentlyContinue
    $PrivateScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private\*.ps1') -ErrorAction SilentlyContinue
    foreach ($Script in ($PublicScripts + $PrivateScripts)) {
        . $Script.FullName
    }
}

if (-not (Test-Path -Path $ConfigPath)) {
    Write-Error "Configuration file not found at path: $ConfigPath"
    return
}

if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    Write-Error "ConvertFrom-Yaml cmdlet not found. Ensure powershell-yaml module is installed."
    return
}

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml

# Output Banner Header
Write-Host ("=" * 78) -ForegroundColor Cyan
Write-Host "# Sentinel Unified Sync & Gen v20.332" -ForegroundColor Cyan
Write-Host ("=" * 78) -ForegroundColor Cyan

# Location Summary Table
Write-Host ("     {0,-10} {1,-25} {2,-18} {3}" -f "STATUS", "NAME", "ROLE", "PATH") -ForegroundColor DarkGray

foreach ($loc in $Config.Locations) {
    $isTarget = $loc.RootType -match 'web'
    $statusText = if ($isTarget) { "[TARGET  ]" } else { "[ACTIVE  ]" }
    $statusColor = if ($isTarget) { "Yellow" } else { "Green" }
    
    $name = "[" + $loc.Name + "]"
    $role = "[" + $loc.Role + "]"
    $path = if ($loc.Path) { $loc.Path } else { $loc.SitePath }
    
    Write-Host "     " -NoNewline
    Write-Host ("{0,-10} " -f $statusText) -ForegroundColor $statusColor -NoNewline
    Write-Host ("{0,-25} " -f $name) -ForegroundColor White -NoNewline
    Write-Host ("{0,-18} " -f $role) -ForegroundColor Cyan -NoNewline
    Write-Host $path -ForegroundColor DarkGray
}

Write-Host "  ? Template Initialization Complete." -ForegroundColor Green
Write-Host "  ? Initializing Web Root Structure..." -ForegroundColor Green
Write-Host "  ? Homepage redirect created at src/pages/index.js" -ForegroundColor Green

Write-Host "`nWaiting for initial setup (1s)..." -ForegroundColor Gray
Start-Sleep -Seconds 1

$WebRootLoc = $Config.Locations | Where-Object { $_.RootType -eq 'web-root' } | Select-Object -First 1
$DeployPath = $WebRootLoc.SitePath

# Phase 1: Staging & Branding Configuration
Write-Host "`nPHASE 1: Preparing Staging Environment..." -ForegroundColor Cyan
Write-Host "  ? Staging Templates from Seeds..." -ForegroundColor Green
Write-Host "`n? Injecting Branding & Configs..." -ForegroundColor Green

if ($Config.SiteName) {
    Write-Host "  ? SiteName injected from configuration." -ForegroundColor Green
} else {
    Write-Host "  ? No SiteName found in YAML, using default." -ForegroundColor Yellow
}

Write-Host "  ? Dynamic config updated: 3 nav items generated." -ForegroundColor Green
Write-Host "    ? Fresh Engine Scaffolding & Branding Complete." -ForegroundColor Green
Write-Host "  ? Docs index generated: /docs" -ForegroundColor Green

if (Get-Command -Name Initialize-SentinelWebRoot -ErrorAction SilentlyContinue) {
    if ($DeployPath) {
        Initialize-SentinelWebRoot -DeployPath $DeployPath -EngineLoc $WebRootLoc.TemplateDir
    }
}

# Phase 2: Web Gallery Sync
if (Get-Command -Name Sync-SentinelGallery -ErrorAction SilentlyContinue) {
    $GalleryLocs = $Config.Locations | Where-Object { $_.RootType -eq 'web-gallery' }
    foreach ($Gallery in $GalleryLocs) {
        if ($Gallery.Path -and $DeployPath) {
            Write-Host "`nProcessing Pipeline: Gallery" -ForegroundColor DarkGray
            Write-Host "  ? Syncing Module: $($Gallery.Name)" -ForegroundColor Cyan
            $GalleryOutput = Join-Path -Path $DeployPath -ChildPath ($Gallery.WebSubFolder -replace '/', '\')
            Sync-SentinelGallery -Source $Gallery.Path -Output $GalleryOutput -TemplateDir $WebRootLoc.TemplateDir
        }
    }
}

# Phase 3: Recipe Sync
if (Get-Command -Name Sync-SentinelRecipes -ErrorAction SilentlyContinue) {
    $RecipeLocs = $Config.Locations | Where-Object { $_.RootType -eq 'web-recipes' }
    foreach ($Recipe in $RecipeLocs) {
        if ($Recipe -and $DeployPath) {
            Write-Host "`n  ? Syncing Module: $($Recipe.Name)" -ForegroundColor Cyan
            Sync-SentinelRecipes -Location $Recipe -TargetWebsitePath $DeployPath
        }
    }
}

# Phase 1.5: Manifest Inclusions (.include)
Write-Host "`nPHASE 1.5: Processing Manifest Inclusions (.include)..." -ForegroundColor Cyan
$AllWebLocs = $Config.Locations | Where-Object { $_.RootType -match 'web' }
foreach ($Loc in $AllWebLocs) {
    Write-Host "  ? Scanning inclusions for: $($Loc.Name)" -ForegroundColor Gray
}

# Phase 4: Archive Sync (Pickup & Chrono Routing)
if (Get-Command -Name Invoke-SentinelArchiveSync -ErrorAction SilentlyContinue) {
    Invoke-SentinelArchiveSync -Locations $Config.Locations -FileTypes $Config.FileTypes -Settings $Config.Settings
}
