[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

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

if (-not (Test-Path -Path $ConfigPath)) {
    Write-Error "CRITICAL: Config file not found at '$ConfigPath'."
    exit 1
}

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "# Sentinel Standalone Website Builder" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

foreach ($Loc in $Config.Locations) {
    if ($Loc.Role -eq 'Website' -and $Loc.SitePath) {
        Write-Host "Clearing website directory: $($Loc.SitePath)" -ForegroundColor Yellow
        if (Test-Path -Path $Loc.SitePath) {
            Remove-Item -Path $Loc.SitePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Installing fresh Docusaurus base..." -ForegroundColor Cyan
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c npx --yes create-docusaurus@latest `"$($Loc.SitePath)`" classic --typescript --skip-install" -NoNewWindow -Wait

        $PkgPath = Join-Path $Loc.SitePath "package.json"
        if (-not (Test-Path $PkgPath)) {
            Start-Sleep -Seconds 2
        }

        if ($Loc.TemplateDir -and (Test-Path -Path $Loc.TemplateDir)) {
            Write-Host "Scaffolding base template..." -ForegroundColor Cyan
            Copy-Item -Path "$($Loc.TemplateDir)\*" -Destination $Loc.SitePath -Recurse -Force
        }

        $BoilerplateFiles = @(
            "$($Loc.SitePath)\src\pages\index.js",
            "$($Loc.SitePath)\src\pages\index.tsx",
            "$($Loc.SitePath)\blog"
        )
        foreach ($Item in $BoilerplateFiles) {
            if (Test-Path $Item) {
                Remove-Item -Path $Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host "Scaffolding content subdirectories (jems-tones, culinary-cuisine, millermade-handcrafted)..." -ForegroundColor Cyan
        foreach ($SubDir in @('jems-tones', 'culinary-cuisine', 'millermade-handcrafted')) {
            $DestSub = Join-Path $Loc.SitePath "docs\$SubDir"
            if (-not (Test-Path $DestSub)) {
                New-Item -Path $DestSub -ItemType Directory -Force | Out-Null
            }
        }
        
        if (Test-Path $PkgPath) {
            Write-Host "Running final dependency install..." -ForegroundColor Cyan
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d `"$($Loc.SitePath)`" && npm install" -NoNewWindow -Wait
            Write-Host "SUCCESS: Website scaffolded and modules linked." -ForegroundColor Green
        } else {
            Write-Error "CRITICAL: package.json still missing in $($Loc.SitePath). Skipping npm install."
        }
    }
}