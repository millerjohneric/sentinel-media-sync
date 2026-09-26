function Start-SentinelSync {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    process {
        $ErrorActionPreference = 'Stop'

        if (-not $ConfigPath -or -not (Test-Path -Path $ConfigPath)) {
            $PossiblePaths = @(
                "$PSScriptRoot\Sentinel-Config.yml",
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
            return
        }

        Write-Host "Running Sentinel Sync using config: $ConfigPath" -ForegroundColor Cyan

        if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
            Write-Error "ConvertFrom-Yaml cmdlet not found. Ensure powershell-yaml module is installed."
            return
        }

        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml

        # Build website first
        if (Get-Command -Name Build-SentinelWebsite -ErrorAction SilentlyContinue) {
            Write-Host "Building Sentinel Website..." -ForegroundColor Cyan
            Build-SentinelWebsite -ConfigPath $ConfigPath
        }

        # Location Summary Table
        Write-Host ("=" * 78) -ForegroundColor Cyan
        Write-Host "# Sentinel Unified Sync & Gen" -ForegroundColor Cyan
        Write-Host ("=" * 78) -ForegroundColor Cyan

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

        $WebRootLoc = $Config.Locations | Where-Object { $_.RootType -eq 'web-root' } | Select-Object -First 1
        $DeployPath = $WebRootLoc.SitePath

        # Phase 0: Purge Website
        if ($Config.PurgeWebsite -eq $true -and $DeployPath -and (Test-Path -Path $DeployPath)) {
            Write-Host "  Purging website directory per configuration: $DeployPath" -ForegroundColor Yellow
            Remove-Item -Path "$DeployPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Phase 1: Staging & Branding Configuration
        Write-Host "`nPHASE 1: Preparing Staging Environment..." -ForegroundColor Cyan
        if ($Config.SiteName) {
            Write-Host "  SiteName injected from configuration." -ForegroundColor Green
        }

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
                    Write-Host ""
                    Write-Host "  Syncing Module: $($Gallery.Name)" -ForegroundColor Cyan
                    Sync-SentinelGallery -Location $Gallery -TargetWebsitePath $DeployPath
                }
            }
        }

        # Phase 3: Recipe Sync (with OCR Pre-processing)
        if (Get-Command -Name Sync-SentinelRecipes -ErrorAction SilentlyContinue) {
            $RecipeLocs = $Config.Locations | Where-Object { $_.RootType -eq 'web-recipes' }
            foreach ($Recipe in $RecipeLocs) {
                if ($Recipe -and $DeployPath) {
                    Write-Host ""
                    Write-Host "   Syncing Module: $($Recipe.Name)" -ForegroundColor Cyan
                    Sync-SentinelRecipes -Location $Recipe -TargetWebsitePath $DeployPath
                }
            }
        }

        # Phase 3.5: Handcrafted / Shop Module Sync
        if (Get-Command -Name Sync-SentinelShop -ErrorAction SilentlyContinue) {
            $ShopLocs = $Config.Locations | Where-Object { $_.Role -eq 'Website' -and $_.Name -eq 'millermade-handcrafted' }
            foreach ($Shop in $ShopLocs) {
                if ($DeployPath) {
                    Write-Host "`nProcessing Pipeline: Shop ($($Shop.Name))" -ForegroundColor DarkGray
                    $StagingTarget = Join-Path -Path $DeployPath -ChildPath 'docs\millermade-handcrafted'
                    Write-Host ""
                    Sync-SentinelShop -StagingPath $StagingTarget -LocationConfig @{ ShopPath = $Shop.Path }
                }
            }
        }

        # Phase 4: Archive Sync (Pickup & Chrono Routing)
        if (Get-Command -Name Invoke-SentinelArchiveSync -ErrorAction SilentlyContinue) {
            Invoke-SentinelArchiveSync -Locations $Config.Locations -FileTypes $Config.FileTypes -Settings $Config.Settings
        }

        # Phase 4.8: Purge Junk Files & Empty Directories
        if (Get-Command -Name Purge-SentinelJunk -ErrorAction SilentlyContinue) {
            Write-Host "`nPurging junk files and cleaning empty directories..." -ForegroundColor Cyan
            Purge-SentinelJunk -Locations $Config.Locations -Exclusions $Config.FileTypes.Exclusions -JunkPatterns $Config.FileTypes.Junk
        }

        Write-Host "`nMISSION COMPLETE" -ForegroundColor Green
    }
}
