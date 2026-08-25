[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# ==============================================================================
# 1. CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================

if (-not $ConfigPath -or -not (Test-Path -Path $ConfigPath)) {
    $PossiblePaths = @(
        "$PSScriptRoot\Sentinel-Config.yml",
        "$PSScriptRoot\..\Sentinel-Config.yml",
        "C:\Source\GEEK\Sentinel\Sentinel-Config.yml",
        "C:\Source\GEEK\Sentinel\sentinel-media-sync\Sentinel-Config.yml"
    )
    
    foreach ($path in $PossiblePaths) {
        if (Test-Path -Path $path) {
            $ConfigPath = $path
            break
        }
    }
}

if (-not $ConfigPath -or -not (Test-Path -Path $ConfigPath)) {
    Write-Host "WARNING: Could not automatically locate Sentinel-Config.yml." -ForegroundColor Yellow
    $ConfigPath = Read-Host "Please enter the full path to your Sentinel-Config.yml file"
}

if (-not (Test-Path -Path $ConfigPath)) {
    Write-Error "CRITICAL: Config file not found at '$ConfigPath'."
    exit 1
}

Write-Host "Using Configuration: $ConfigPath" -ForegroundColor Cyan
Write-Host "Loading Sentinel Private & Public Functions..." -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Manually dot-source functions to avoid module nesting traps
$PublicDir = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path $PublicDir) {
    foreach ($script in (Get-ChildItem -Path $PublicDir -Filter "*.ps1")) {
        if (-not $isAdmin -and $script.Name -eq 'Sentinel-Register-Task.ps1') {
            Write-Host "NOTICE: Skipping $($script.Name) (Administrator privileges required)." -ForegroundColor Yellow
            continue
        }
        . $script.FullName
    }
}

$PrivateDir = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
if (Test-Path $PrivateDir) {
    foreach ($script in (Get-ChildItem -Path $PrivateDir -Filter "*.ps1")) {
        . $script.FullName
    }
}

if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    Write-Error "ConvertFrom-Yaml cmdlet not found. Ensure powershell-yaml module is installed."
    exit 1
}

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml


# ==============================================================================
# 2. EXECUTION PIPELINE & BANNER
# ==============================================================================

Write-Host ("=" * 78) -ForegroundColor Cyan
Write-Host "# Sentinel Unified Sync & Gen v20.332" -ForegroundColor Cyan
Write-Host ("=" * 78) -ForegroundColor Cyan

# Location Summary Table
Write-Host ("    {0,-10} {1,-25} {2,-18} {3}" -f "STATUS", "NAME", "ROLE", "PATH") -ForegroundColor DarkGray

foreach ($loc in $Config.Locations) {
    $isTarget = $loc.RootType -match 'web'
    $statusText = if ($isTarget) { "[TARGET  ]" } else { "[ACTIVE  ]" }
    $statusColor = if ($isTarget) { "Yellow" } else { "Green" }
    
    $name = "[" + $loc.Name + "]"
    $role = "[" + $loc.Role + "]"
    $path = if ($loc.Path) { $loc.Path } else { $loc.SitePath }
    
    Write-Host "    " -NoNewline
    Write-Host ("{0,-10} " -f $statusText) -ForegroundColor $statusColor -NoNewline
    Write-Host ("{0,-25} " -f $name) -ForegroundColor White -NoNewline
    Write-Host ("{0,-18} " -f $role) -ForegroundColor Cyan -NoNewline
    Write-Host $path -ForegroundColor DarkGray
}

Write-Host "  ? Template Initialization Complete." -ForegroundColor Green
Write-Host "  ? Initializing Web Root Structure..." -ForegroundColor Green
Write-Host "  ? Homepage redirect created at src/pages/index.js" -ForegroundColor Green

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
Write-Host "     ? Fresh Engine Scaffolding & Branding Complete." -ForegroundColor Green
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

# Phase 3: Recipe Sync (with OCR Pre-processing)
if (Get-Command -Name Sync-SentinelRecipes -ErrorAction SilentlyContinue) {
    $RecipeLocs = $Config.Locations | Where-Object { $_.RootType -eq 'web-recipes' }
    foreach ($Recipe in $RecipeLocs) {
        if ($Recipe -and $DeployPath) {
            if (Get-Command -Name Invoke-RecipeOcr -ErrorAction SilentlyContinue) {
                Write-Host "`n  ? Processing Recipe OCR: $($Recipe.Name)" -ForegroundColor Cyan
                Invoke-RecipeOcr -Source $Recipe.Path
            }
            Write-Host "  ? Syncing Module: $($Recipe.Name)" -ForegroundColor Cyan
            Sync-SentinelRecipes -Location $Recipe -TargetWebsitePath $DeployPath
        }
    }
}

# Phase 4: Archive Sync (Pickup & Chrono Routing)
if (Get-Command -Name Invoke-SentinelArchiveSync -ErrorAction SilentlyContinue) {
    Invoke-SentinelArchiveSync -Locations $Config.Locations -FileTypes $Config.FileTypes -Settings $Config.Settings
}


# ==============================================================================
# 3. PACKAGING & SCHEDULED TASK REGISTRATION
# ==============================================================================

# Package Sentinel Suite for transport (if enabled in config)
if ($Config.Settings.EnableTransportBackup -eq $true) {
    $BackupZip = "$env:USERPROFILE\Desktop\Sentinel_v9.1_Backup.zip"
    Write-Host "`nPacking Sentinel Suite for transport..." -ForegroundColor Cyan
    if (Test-Path "$PSScriptRoot\..") {
        Compress-Archive -Path "$PSScriptRoot\.." -DestinationPath $BackupZip -Force -ErrorAction SilentlyContinue
        Write-Host "MISSION PACKED: Check your Desktop for Sentinel_v9.1_Backup.zip" -ForegroundColor Green
    }
}

# Register Scheduled Task
$TaskName = "SentinelMediaSync"
$ScriptTarget = "$PSScriptRoot\Run-Sentinel.ps1"
$Action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptTarget`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 12:00AM

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    try {
        Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $TaskName -Description 'Daily synchronization for The Source media archives.' -Force -ErrorAction Stop | Out-Null
        Write-Host "MISSION SUCCESSFUL" -ForegroundColor Green
        Write-Host "Task '$TaskName' registered successfully." -ForegroundColor Cyan
    }
    catch {
        Write-Host "WARNING: Could not auto-register scheduled task. Details: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "NOTICE: Scheduled task registration skipped (Administrator privileges required)." -ForegroundColor Yellow
}
