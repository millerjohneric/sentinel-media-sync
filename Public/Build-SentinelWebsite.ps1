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
            $NpxCmd = (Get-Command npx -ErrorAction SilentlyContinue).Source
            if (-not $NpxCmd) {
                $NpxCmd = "npx.cmd"
            }
            # Use PowerShell invocation to handle spaces properly
            $ScriptBlock = {
                param($npxPath, $sitePath)
                & $npxPath --yes create-docusaurus@latest $sitePath classic --typescript --skip-install
            }
            & $ScriptBlock $NpxCmd $Loc.SitePath

            $PkgPath = Join-Path $Loc.SitePath "package.json"
            if (-not (Test-Path $PkgPath)) {
                Start-Sleep -Seconds 2
            }
            
            $BoilerplateFiles = @(
                "$($Loc.SitePath)\src\pages\index.js",
                "$($Loc.SitePath)\src\pages\index.tsx",
                "$($Loc.SitePath)\blog",
                "$($Loc.SitePath)\docs\intro.md",
                "$($Loc.SitePath)\docs\intro.mdx",
                "$($Loc.SitePath)\docs\tutorial",
                "$($Loc.SitePath)\docs\tutorial-basics",
                "$($Loc.SitePath)\docs\tutorial-extras",
                "$($Loc.SitePath)\sidebars.js",
                "$($Loc.SitePath)\sidebars.ts",
                "$($Loc.SitePath)\docusaurus.config.js",
                "$($Loc.SitePath)\docusaurus.config.ts",
                "$($Loc.SitePath)\README.md",
                "$($Loc.SitePath)\static\img"
            )
            foreach ($Item in $BoilerplateFiles) {
                if (Test-Path $Item) {
                    Remove-Item -Path $Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            if ($Loc.TemplateDir -and (Test-Path -Path $Loc.TemplateDir)) {
                Write-Host "Scaffolding base template..." -ForegroundColor Cyan
                
                # Copy core-config files directly to the Docusaurus root
                $CoreConfigDir = Join-Path $Loc.TemplateDir "core-config"
                if (Test-Path $CoreConfigDir) {
                    Copy-Item -Path "$CoreConfigDir\*" -Destination $Loc.SitePath -Recurse -Force

                    # Deploy custom.css to src/css/custom.css
                    $CustomCss = Join-Path $CoreConfigDir "custom.css"
                    $DestCssDir = Join-Path $Loc.SitePath "src\css"
                    if (Test-Path $CustomCss) {
                        if (-not (Test-Path $DestCssDir)) {
                            try { New-Item -Path $DestCssDir -ItemType Directory -Force | Out-Null }
                            catch { Write-Warning "Could not create CSS directory: $_" }
                        }
                        if (Test-Path $DestCssDir) {
                            try { Copy-Item -Path $CustomCss -Destination "$DestCssDir\custom.css" -Force }
                            catch { Write-Warning "Could not copy custom.css: $_" }
                        }
                    }

                    # Deploy index.js to src/pages/index.js (redirect / home)
                    $HomePage = Join-Path $CoreConfigDir "index.js"
                    $DestPagesDir = Join-Path $Loc.SitePath "src\pages"
                    if (Test-Path $HomePage) {
                        if (-not (Test-Path $DestPagesDir)) {
                            try { New-Item -Path $DestPagesDir -ItemType Directory -Force | Out-Null }
                            catch { Write-Warning "Could not create pages directory: $_" }
                        }
                        if (Test-Path $DestPagesDir) {
                            try { Copy-Item -Path $HomePage -Destination "$DestPagesDir\index.js" -Force }
                            catch { Write-Warning "Could not copy index.js: $_" }
                        }
                    }
                }

                # Copy components to src/components
                $ComponentsDir = Join-Path $Loc.TemplateDir "components"
                if (Test-Path $ComponentsDir) {
                    $DestComponentsDir = Join-Path $Loc.SitePath "src\components"
                    if (-not (Test-Path $DestComponentsDir)) {
                        try { New-Item -Path $DestComponentsDir -ItemType Directory -Force | Out-Null }
                        catch { Write-Warning "Could not create components directory: $_" }
                    }
                    if (Test-Path $DestComponentsDir) {
                        try { Copy-Item -Path "$ComponentsDir\*" -Destination $DestComponentsDir -Recurse -Force }
                        catch { Write-Warning "Could not copy components: $_" }
                    }
                }

                # Copy branding assets to static/img if present
                $BrandingDir = Join-Path $Loc.TemplateDir "branding"
                if (Test-Path $BrandingDir) {
                    $StaticImgDir = Join-Path $Loc.SitePath "static\img"
                    if (-not (Test-Path $StaticImgDir)) {
                        try { New-Item -Path $StaticImgDir -ItemType Directory -Force | Out-Null }
                        catch { Write-Warning "Could not create static\img directory: $_" }
                    }
                    $BrandingImg = Join-Path $BrandingDir "img"
                    if (Test-Path $BrandingImg) {
                        try { Copy-Item -Path "$BrandingImg\*" -Destination $StaticImgDir -Recurse -Force }
                        catch { Write-Warning "Could not copy branding images: $_" }
                    } else {
                        try { Copy-Item -Path "$BrandingDir\*" -Destination $StaticImgDir -Recurse -Force }
                        catch { Write-Warning "Could not copy branding assets: $_" }
                    }
                }

                # Copy overview doc index if available
                $OverviewDoc = Join-Path $Loc.TemplateDir "content-seeds\docs\index - overview.md"
                $DestDocsDir = Join-Path $Loc.SitePath "docs"
                if (Test-Path $OverviewDoc) {
                    try { Copy-Item -Path $OverviewDoc -Destination "$DestDocsDir\index.md" -Force }
                    catch { Write-Warning "Could not copy overview doc: $_" }
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