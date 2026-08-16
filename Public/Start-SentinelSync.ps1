function Start-SentinelSync {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Sentinel-Config.yml')
    )

    $Global:SentinelTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $StartTime = [System.DateTime]::Now 
    $Global:YamlData = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml
    $globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # --- PATH MAPPING ---
    $Engine = $Global:YamlData.Locations | Where-Object { $_.RootType -eq 'web-root' }
    $TargetWebsitePath = $Engine.Path 
    $BuildPath = $Engine.Path 
    $Settings = $Global:YamlData.Settings

    if ([string]::IsNullOrWhiteSpace($TargetWebsitePath)) {
        Write-Host "CRITICAL ERROR: Could not resolve TargetWebsitePath from config!" -ForegroundColor Red
        return
    }

    $CurrentRevision = Get-SentinelRevision -ScriptPath $PSScriptRoot
    $ToolHeader = "Sentinel Unified Sync & Gen $CurrentRevision"

    Clear-Host
    Write-Host "==============================================================================" -ForegroundColor Gray
    Write-Host "# $ToolHeader" -ForegroundColor Yellow
    Write-Host "==============================================================================" -ForegroundColor Gray

    # --- PHASE 0: INITIALIZATION ---
    Write-SentinelPhase0 -YamlData $Global:YamlData

    # --- OCR PREPROCESSING FOR RECIPES ---
    $OcrLocations = $Global:YamlData.Locations | Where-Object { $_.OCR -eq $true }
    foreach ($loc in $OcrLocations) {
        Write-Host "`n  $($Global:Icons.Arrow) OCR preprocessing for $($loc.Name)" -ForegroundColor Cyan
        Invoke-SentinelRecipeOcr -Source $loc.Path
        $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'Sentinel-Config.yml'
        $ConfigRaw = [System.IO.File]::ReadAllText($ConfigPath)
        $ConfigRaw = $ConfigRaw -replace "'OCR': true", "'OCR': false"
        [System.IO.File]::WriteAllText($ConfigPath, $ConfigRaw, [System.Text.UTF8Encoding]::new($false))
    }
    Initialize-SentinelSecrets
    Initialize-SentinelTemplates -TemplateDir $Engine.TemplateDir
    Initialize-SentinelWebRoot -BuildPath $BuildPath -DeployPath $TargetWebsitePath -EngineLoc $Engine
    Write-SentinelHomepageRedirect -SitePath $TargetWebsitePath

    Write-Host "`nWaiting for initial setup (1s)..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1

    # --- PHASE 1: PREPARING STAGING ENVIRONMENT ---
    Write-Host "`nPHASE 1: Preparing Staging Environment..." -ForegroundColor Cyan
    
    $WebLoc = $Global:YamlData.Locations | Where-Object { $_.RootType -eq 'web-root' }
    if ($null -ne $WebLoc) {
        # 1. FIXED PURGE: Clear the directory tree entirely using a clean staging directory mirror
        $PackageCheck = Join-Path -Path $WebLoc.Path -ChildPath "package.json"
        if ($WebLoc.PurgeWebsite -and (Test-Path -Path $WebLoc.Path)) {
            Write-Host "  $($Global:Icons.Warning) Purging Prep Path: $($WebLoc.Path)" -ForegroundColor Yellow
            
            # Kill any background process locks before attempting folder modifications
            $Port3000Pid = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess
            if ($Port3000Pid) { Stop-Process -Id $Port3000Pid -Force -ErrorAction SilentlyContinue }

            $EmptyTemp = Join-Path -Path $env:TEMP -ChildPath "sentinel_purge_tmp"
            New-Item -Path $EmptyTemp -ItemType Directory -Force | Out-Null
            robocopy $EmptyTemp $WebLoc.Path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
            Remove-Item -Path $WebLoc.Path -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $EmptyTemp -Recurse -Force -ErrorAction SilentlyContinue

            # Auto-reset PurgeWebsite to false so next run is incremental
            $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'Sentinel-Config.yml'
            $ConfigRaw = [System.IO.File]::ReadAllText($ConfigPath)
            $ConfigRaw = $ConfigRaw -replace "'PurgeWebsite': true", "'PurgeWebsite': false"
            [System.IO.File]::WriteAllText($ConfigPath, $ConfigRaw, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  $($Global:Icons.Check) PurgeWebsite auto-reset to false." -ForegroundColor Gray
        }
    
        # 2. SELF-HEALING: Re-scaffold smoothly if package.json is missing or was just purged
        $PackagePath = Join-Path -Path $WebLoc.Path -ChildPath "package.json"
        if (-not (Test-Path -Path $PackagePath)) {
            Write-Host "  $($Global:Icons.Error) Engine framework missing or purged. Re-scaffolding..." -ForegroundColor Yellow
            
            if (Test-Path -Path $WebLoc.Path) {
                $EmptyTemp = Join-Path -Path $env:TEMP -ChildPath "sentinel_empty_tmp"
                New-Item -Path $EmptyTemp -ItemType Directory -Force | Out-Null
                robocopy $EmptyTemp $WebLoc.Path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
                Remove-Item -Path $WebLoc.Path -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $EmptyTemp -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $ParentDir = Split-Path -Path $WebLoc.Path -Parent
            $FolderName = Split-Path -Path $WebLoc.Path -Leaf
            Push-Location -Path $ParentDir
            npx --yes create-docusaurus@latest $FolderName classic --javascript --skip-install
            Pop-Location

            if (-not (Test-Path -Path $PackagePath)) {
                Write-Host "  $($Global:Icons.Error) CRITICAL: Scaffold failed. package.json not found at $PackagePath" -ForegroundColor Red
                return
            }

            # Fix BOM: rewrite package.json without BOM so webpack can parse it smoothly
            $PkgContent = Get-Content -Path $PackagePath -Raw
            [System.IO.File]::WriteAllText($PackagePath, $PkgContent, [System.Text.UTF8Encoding]::new($false))
        }

        # 3. TEMPLATE STAGING: Ensures .md templates exist for Phase 2
        $StagingCoreConfig = Join-Path -Path $WebLoc.Path -ChildPath "core-config"
        if (-not (Test-Path -Path $StagingCoreConfig)) { New-Item -Path $StagingCoreConfig -ItemType Directory -Force | Out-Null }
        
        Write-Host "  $($Global:Icons.Check) Staging Templates from Seeds..." -ForegroundColor Cyan
        robocopy (Join-Path -Path $WebLoc.TemplateDir -ChildPath "content-seeds") $StagingCoreConfig /S /E /NFL /NDL /NJH /NJS /nc /ns /np

        # 4. BOILERPLATE CLEANUP: Remove Docusaurus defaults
        $Boilerplate = @("docs/intro.md", "docs/intro.mdx", "docs/tutorial-basics", "docs/tutorial-extras", "blog")
        foreach ($Item in $Boilerplate) {
            $PathToRemove = Join-Path -Path $WebLoc.Path -ChildPath $Item
            if (Test-Path -Path $PathToRemove) { 
                Remove-Item -Path $PathToRemove -Recurse -Force 
                Write-Host "    - Cleaned boilerplate: $Item" -ForegroundColor DarkGray
            }
        }

        # 5. BRANDING: Apply custom configs, CSS, and logo
        if (Test-Path -Path $WebLoc.TemplateDir) {
            Invoke-SentinelBranding -SitePath $WebLoc.Path -TemplateDir $WebLoc.TemplateDir
            Write-SentinelDocusaurusConfig -SitePath $WebLoc.Path -YamlData $Global:YamlData
        }
        
        if (Test-Path -Path (Join-Path -Path $WebLoc.Path -ChildPath "package.json")) {
            Write-Host "    $($Global:Icons.Check) Fresh Engine Scaffolding & Branding Complete." -ForegroundColor Green
            Write-SentinelDocsIndex -SitePath $WebLoc.Path -YamlData $Global:YamlData
        } else {
            Write-Host "    $($Global:Icons.Error) Scaffold FAILED. Check network/permissions." -ForegroundColor Red
        }
    }

    # Now run the media sync to populate /docs/ in the Prep folder
    $MediaStats = Sync-SentinelMedia -Locations $Global:YamlData.Locations -TargetWebsitePath $WebLoc.Path -Settings $Settings

    # --- PHASE 1.5: MANIFEST INCLUSIONS ---
    Invoke-SentinelCsvInclusions -Locations $Global:YamlData.Locations

    # --- ARCHIVE SYNC: Route pickup zones to dated archive folders ---
    Invoke-SentinelArchiveSync -Locations $Global:YamlData.Locations -FileTypes $Global:YamlData.FileTypes -Settings $Settings

    # --- PHASE 2: GENERATING ---
    Write-Host "`nPHASE 2: Generating Website Content..." -ForegroundColor Cyan
    
    foreach ($loc in $Global:YamlData.Locations) {
        if ($loc.Template) {
            Write-Host "  $($Global:Icons.Arrow) Processing Pipeline: $($loc.Name)" -ForegroundColor Gray
            Invoke-SentinelWebPipeline `
                -TemplatePath (Join-Path -Path $WebLoc.Path -ChildPath $loc.Template) `
                -OutputPath $WebLoc.Path `
                -LocationConfig $loc
        }
    }

    # --- PHASE 3: FINALIZING STAGING ---
    Write-Host "`nPHASE 3: Finalizing Staging..." -ForegroundColor Cyan
    
    $PackageJson = Join-Path -Path $WebLoc.Path -ChildPath "package.json"
    if (-not (Test-Path -Path $PackageJson)) {
        Write-Host "  $($Global:Icons.Error) CRITICAL: package.json missing in Prep. Aborting." -ForegroundColor Red
        return
    }

    # Ensure node_modules exist in Prep first
    $PrepNM = Join-Path -Path $WebLoc.Path -ChildPath "node_modules"
    if (-not (Test-Path -Path $PrepNM) -or $WebLoc.PurgeWebsite) {
        Write-Host "  $($Global:Icons.Warning) Installing dependencies in Prep lab..." -ForegroundColor Yellow
        Push-Location -Path $WebLoc.Path
        npm install --no-audit --no-fund
        Pop-Location
    }

    # Unlock and write sidebars
    $SidebarPath = Join-Path -Path $WebLoc.Path -ChildPath "sidebars.js"
    if (Test-Path -Path $SidebarPath) { Set-ItemProperty -Path $SidebarPath -Name Attributes -Value "Normal" }
    Write-SentinelSidebars -SitePath $WebLoc.Path

    # Stop Docusaurus before deployment to prevent file lock issues
    Write-Host "  $($Global:Icons.Arrow) Stopping Docusaurus before deployment..." -ForegroundColor Gray
    $Port3000Pid = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess
    if ($Port3000Pid) { Stop-Process -Id $Port3000Pid -Force -ErrorAction SilentlyContinue }
    Get-Process -Name node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # DEPLOY: Mirror to Production
    # Resolve target path — network or local based on config switch
    $DeployTarget = if ($WebLoc.UseNetworkPath -and -not [string]::IsNullOrWhiteSpace($WebLoc.SitePathNetwork)) {
        $WebLoc.SitePathNetwork
    } else {
        $WebLoc.SitePath
    }
    Write-Host "  $($Global:Icons.Check) Deploying to Production: $DeployTarget" -ForegroundColor Green
    robocopy $WebLoc.Path $DeployTarget /MIR /MT:8 /XD node_modules .git /NFL /NDL /NJH /NJS /nc /ns /np

    # Verify node_modules exist in Production
    if (-not (Test-Path -Path (Join-Path -Path $DeployTarget -ChildPath "node_modules"))) {
        Write-Host "  $($Global:Icons.Warning) Initializing Production dependencies..." -ForegroundColor Yellow
        robocopy $PrepNM (Join-Path -Path $DeployTarget -ChildPath "node_modules") /E /MT:8 /NFL /NDL /NJH /NJS /nc /ns /np
    }

    # --- PHASE 4: AUTO-LAUNCH ---
    if ($WebLoc.AutoLaunch -or $true) { 
        Start-SentinelProduction -SitePath $DeployTarget
    }

    # Display Final Report
    Write-SentinelReport -Stats $MediaStats -Watch $Global:SentinelTimer -RemoteUrl $Global:YamlData.Settings.RemoteUrl
}