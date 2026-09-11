function Build-SentinelWebsite {
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
                # Stop processes that lock files inside the target directory
                Get-Process -Name "node" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1

                # Clean out existing contents prior to removal
                Get-ChildItem -Path $Loc.SitePath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $Loc.SitePath -Recurse -Force -ErrorAction SilentlyContinue
            }

            Write-Host "Installing fresh Docusaurus base..." -ForegroundColor Cyan
            $NodePath = (Get-Command node).Source
            $NpxCliPath = "C:\Program Files\nodejs\node_modules\npm\bin\npx-cli.js"
            Start-Process -FilePath "$NodePath" -ArgumentList "`"$NpxCliPath`"", "--yes", "create-docusaurus@latest", "`"$($Loc.SitePath)`"", "classic", "--typescript", "--skip-install" -NoNewWindow -Wait

            $PkgPath = Join-Path $Loc.SitePath "package.json"
            if (-not (Test-Path $PkgPath)) {
                Start-Sleep -Seconds 2
            }

            if ($Loc.TemplateDir -and (Test-Path -Path $Loc.TemplateDir)) {
                Write-Host "Scaffolding base template..." -ForegroundColor Cyan
                $TemplateItems = Join-Path $Loc.TemplateDir "*"
                Copy-Item -Path $TemplateItems -Destination $Loc.SitePath -Recurse -Force
            }

            $BoilerplateFiles = @(
                "$($Loc.SitePath)\src\pages\index.js",
                "$($Loc.SitePath)\src\pages\index.tsx",
                "$($Loc.SitePath)\blog",
                "$($Loc.SitePath)\docs\intro.md",
                "$($Loc.SitePath)\docs\tutorial",
                "$($Loc.SitePath)\docs\tutorial-basics",
                "$($Loc.SitePath)\docs\tutorial-extras",
                "$($Loc.SitePath)\sidebars.js",
                "$($Loc.SitePath)\README.md",
                "$($Loc.SitePath)\static\img"
            )
            foreach ($Item in $BoilerplateFiles) {
                if (Test-Path $Item) {
                    Remove-Item -Path $Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            Write-Host "Scaffolding content subdirectories..." -ForegroundColor Cyan
            $SubDirs = @('jems-tones', 'culinary-cuisine', 'millermade-handcrafted')
            if ($Config.Locations) {
                $SubDirs = $Config.Locations | Where-Object { $_.WebSubFolder -and $_.RootType -match 'web' } | ForEach-Object { $_.WebSubFolder.Split('/')[-1] }
            }
            foreach ($SubDir in $SubDirs) {
                $DestSub = Join-Path $Loc.SitePath "docs\$SubDir"
                if (-not (Test-Path $DestSub)) {
                    New-Item -Path $DestSub -ItemType Directory -Force | Out-Null
                }
            }
            
            if (Test-Path $PkgPath) {
                Write-Host "Running final dependency install..." -ForegroundColor Cyan
                $cwd = $Loc.SitePath
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d `"$cwd`" && npm install" -WorkingDirectory $cwd -NoNewWindow -Wait
                Write-Host "SUCCESS: Website scaffolded and modules linked." -ForegroundColor Green
            } else {
                Write-Error "CRITICAL: package.json still missing in $($Loc.SitePath). Skipping npm install."
            }
        }
    }
}