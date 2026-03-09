# ==============================================================================
# Sentinel Core v20.128
# ==============================================================================

$Global:Icons = @{
    'Arrow'   = [char]0x2192
    'Check'   = [char]0x2714
    'Warning' = [char]0x26A0
    'Error'   = [char]0x2718
}

# --- CORE ENGINE FUNCTIONS ---

function Global:Initialize-SentinelWebRoot {
    param([string]$BuildPath, [string]$DeployPath, $EngineLoc)
    Write-Host "  $($Global:Icons.Check) Initializing Web Root Structure..." -ForegroundColor Gray
    
    # Create the base directory if it doesn't exist
    if (!(Test-Path $DeployPath)) { 
        New-Item -Path $DeployPath -ItemType Directory -Force | Out-Null 
    }

    # These are the essential Docusaurus folders
    $Required = @("docs", "static", "src", "src/pages")
    foreach ($Folder in $Required) {
        $P = Join-Path $DeployPath $Folder
        if (!(Test-Path $P)) { 
            New-Item $P -ItemType Directory -Force | Out-Null 
            Write-Host "    + Created: $Folder" -ForegroundColor DarkGray
        }
    }
}

function Global:Sync-SentinelRecipes {
    param($Source, $Output, $TemplateDir)

    # 1. Load the Recipe Card Template
    $TemplateFile = Join-Path $TemplateDir "core-config\recipe-card.md"
    if (!(Test-Path $TemplateFile)) {
        Write-Host "    $($Global:Icons.Error) Recipe Template missing: $TemplateFile" -ForegroundColor Red
        return
    }
    $TemplateContent = Get-Content $TemplateFile -Raw

    # 2. Process Files (Recursive to handle sub-folders like /meals/dinners)
    $RecipeFiles = Get-ChildItem -Path $Source -Filter *.yml -Recurse
    
    foreach ($File in $RecipeFiles) {
        $Data = Get-Content $File.FullName -Raw | ConvertFrom-Yaml
        $FinalContent = $TemplateContent

        # --- STRING ENFORCEMENT ---
        [string]$Title = if ($Data.Title) { $Data.Title } else { $File.BaseName }
        $CleanTitle = $Title.Trim() -replace "['""]", ""

        $FinalContent = $FinalContent.Replace("{{title}}", $CleanTitle)

        # Map Ingredients/Instructions (Handled as strings)
        foreach ($Prop in $Data.PSObject.Properties) {
            [string]$Val = if ($null -ne $Prop.Value) { $Prop.Value } else { "" }
            $FinalContent = $FinalContent.Replace("{{$($Prop.Name)}}", $Val)
        }

        # 3. Preserve Folder Structure in Output
        $RelativePath = $File.DirectoryName.Replace($Source, "").TrimStart('\')
        $TargetFolder = Join-Path $Output $RelativePath
        if (!(Test-Path $TargetFolder)) { New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null }

        $TargetPath = Join-Path $TargetFolder "$($File.BaseName).md"
        $FinalContent | Out-File -FilePath $TargetPath -Encoding utf8 -Force
    }
    Write-Host "    $($Global:Icons.Check) Recipe Module: $($RecipeFiles.Count) cards generated." -ForegroundColor Gray
}
function Global:Sync-SentinelGallery {
    param($Source, $Output, $TemplatePath)
    $TemplateContent = Get-Content -Path $TemplatePath -Raw -ErrorAction SilentlyContinue
    if (!$TemplateContent) { return }

    $MediaFiles = Get-ChildItem -Path $Source -Include "*.jpg","*.png","*.webp" -Recurse
    foreach ($File in $MediaFiles) {
        $RelativePath = $File.DirectoryName.Replace($Source, "").TrimStart('\')
        $TargetSubDir = if ($RelativePath) { Join-Path $Output $RelativePath } else { $Output }
        if (!(Test-Path $TargetSubDir)) { New-Item $TargetSubDir -ItemType Directory -Force | Out-Null }

        # Single quotes used for keys as requested
        $ImgMarkup = "'![](/img/$($File.Directory.Name)/$($File.Name))'"
        $FinalContent = $TemplateContent.Replace("{{title}}", $File.BaseName).Replace("{{slug}}", $File.BaseName).Replace("{{images_list}}", $ImgMarkup)
        
        $TargetPath = Join-Path $TargetSubDir "$($File.BaseName).md"
        $FinalContent | Out-File -FilePath $TargetPath -Encoding utf8
        
        # UPDATED: Show absolute path for transparency
        Write-Host "    $($Global:Icons.Check) Generated: $TargetPath" -ForegroundColor Gray
    }
}

# --- ORCHESTRATION ENGINE ---
function Global:Start-SentinelSync {
    [CmdletBinding()]
    param([string]$ConfigPath = (Join-Path $PSScriptRoot 'Sentinel-Config.yml'))

    $Global:SentinelTimer = [System.Diagnostics.Stopwatch]::StartNew()
    # FIX: Capture the StartTime object here
    $StartTime = [DateTime]::Now 
    $Global:YamlData = Get-Content $ConfigPath -Raw | ConvertFrom-Yaml
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
    Initialize-SentinelSecrets
    Initialize-SentinelTemplates -TemplateDir $Engine.TemplateDir
    Initialize-SentinelWebRoot -BuildPath $BuildPath -DeployPath $TargetWebsitePath -EngineLoc $Engine
    Write-SentinelHomepageRedirect -SitePath $TargetWebsitePath

    Write-Host "`nWaiting for user interrupt (1s)..." -ForegroundColor DarkGray
    $Timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($Timer.Elapsed.TotalSeconds -lt 1) {
        if ([System.Console]::KeyAvailable) { $null = [System.Console]::ReadKey($true); return }
        Start-Sleep -Milliseconds 100 
    }

    # --- PHASE 1: PREPARING STAGING ENVIRONMENT ---
    Write-Host "`nPHASE 1: Preparing Staging Environment..." -ForegroundColor Cyan

    $WebLoc = $Global:YamlData.Locations | Where-Object { $_.RootType -eq 'web-root' }
    if ($null -ne $WebLoc) {
        # 1. Purge Prep Path (Staging)
        if ($WebLoc.PurgeWebsite -and (Test-Path $WebLoc.Path)) {
            Write-Host "  $($Global:Icons.Warning) Purging Prep Path: $($WebLoc.Path)" -ForegroundColor Yellow
            Get-ChildItem -Path $WebLoc.Path -Exclude "node_modules" | Remove-Item -Recurse -Force
        }

        # 2. SELF-HEALING: Re-scaffold if package.json is missing
        if (!(Test-Path (Join-Path $WebLoc.SitePath "package.json"))) {
            Write-Host "  $($Global:Icons.Error) Engine framework missing. Re-scaffolding..." -ForegroundColor Yellow
            
            # npx fails if the dir exists. We must remove it to allow a clean scaffold.
            if (Test-Path $WebLoc.SitePath) { 
                Remove-Item $WebLoc.SitePath -Recurse -Force 
            }
            
            # Run scaffold (using --yes to skip prompts)
            $ParentDir = Split-Path $WebLoc.SitePath
            Push-Location $ParentDir
            npx --yes create-docusaurus@latest website classic --javascript --skip-install
            Pop-Location

            # v21.119 CLEANUP: Remove Docusaurus Boilerplate immediately
            $Boilerplate = @("docs/intro.md", "docs/tutorial-basics", "docs/tutorial-extras", "blog")
            foreach ($Item in $Boilerplate) {
                $PathToRemove = Join-Path $WebLoc.SitePath $Item
                if (Test-Path $PathToRemove) { 
                    Remove-Item $PathToRemove -Recurse -Force 
                    Write-Host "    - Cleaned boilerplate: $Item" -ForegroundColor DarkGray
                }
            }

            # v21.119 BRANDING: Apply your custom configs, CSS, and logo
            if (Test-Path $WebLoc.TemplateDir) {
                Invoke-SentinelBranding -SitePath $WebLoc.SitePath -TemplateDir $WebLoc.TemplateDir
                Write-SentinelDocusaurusConfig -SitePath $WebLoc.SitePath -YamlData $Global:YamlData
            }
            
            if (Test-Path (Join-Path $WebLoc.SitePath "package.json")) {
                Write-Host "    $($Global:Icons.Check) Fresh Engine Scaffolding & Branding Complete." -ForegroundColor Green
            } else {
                Write-Host "    $($Global:Icons.Error) Scaffold FAILED. Check network/permissions." -ForegroundColor Red
            }
        }

        # 3. Mirror Engine to Prep
        Write-Host "  $($Global:Icons.Check) Syncing Engine to Prep..." -ForegroundColor Cyan
        # We add /MT:8 for speed and /R:3 /W:5 for retry resilience
        robocopy $WebLoc.SitePath $WebLoc.Path /S /E /MT:8 /R:3 /W:5 /XD docs node_modules .git /NFL /NDL /NJH /NJS /nc /ns /np
    }

    # Now run the media sync to populate /docs/ in the Prep folder
    $MediaStats = Sync-SentinelMedia -Locations $Global:YamlData.Locations -TargetWebsitePath $WebLoc.Path -Settings $Settings
    # --- PHASE 2: GENERATING ---
    Write-Host "`nPHASE 2: Generating Website Content..." -ForegroundColor Cyan
    
    foreach ($loc in $Global:YamlData.Locations) {
        if ($loc.Template) {
            Write-Host "  $($Global:Icons.Arrow) Processing Pipeline: $($loc.Name)" -ForegroundColor Gray
            
            # Pass the Prep Path (Staging) as TemplateDir, and the Docs root as Target
            Invoke-SentinelWebPipeline `
                -loc $loc `
                -TemplateDir $WebLoc.Path `
                -TargetWebsitePath $WebLoc.Path
        }
    }

    # --- PHASE 3: FINALIZING STAGING ---
    Write-Host "`nPHASE 3: Finalizing Staging..." -ForegroundColor Cyan
    
    $PackageJson = Join-Path $WebLoc.Path "package.json"
    if (!(Test-Path $PackageJson)) {
        Write-Host "  $($Global:Icons.Error) CRITICAL: package.json missing in Prep. Aborting." -ForegroundColor Red
        return
    }

    # Ensure node_modules exist in Prep first
    $PrepNM = Join-Path $WebLoc.Path "node_modules"
    if (!(Test-Path $PrepNM) -or $WebLoc.PurgeWebsite) {
        Write-Host "  $($Global:Icons.Warning) Installing dependencies in Prep lab..." -ForegroundColor Yellow
        Push-Location $WebLoc.Path
        npm install --no-audit --no-fund
        Pop-Location
    }

    # Unlock and write sidebars
    $SidebarPath = Join-Path $WebLoc.Path "sidebars.js"
    if (Test-Path $SidebarPath) { Set-ItemProperty -Path $SidebarPath -Name Attributes -Value "Normal" }
    Write-SentinelSidebars -SitePath $WebLoc.Path

    # DEPLOY: Mirror to Production (C:\Source_Studio\website)
    Write-Host "  $($Global:Icons.Check) Deploying to Production: $($WebLoc.SitePath)" -ForegroundColor Green
    # We mirror everything EXCEPT node_modules to keep the sync fast...
    robocopy $WebLoc.Path $WebLoc.SitePath /MIR /MT:8 /XD node_modules .git /NFL /NDL /NJH /NJS /nc /ns /np

    # ...BUT we then verify node_modules exist in Production. 
    # If missing, we do a targeted copy of just that folder.
    if (!(Test-Path (Join-Path $WebLoc.SitePath "node_modules"))) {
        Write-Host "  $($Global:Icons.Warning) Initializing Production dependencies..." -ForegroundColor Yellow
        # This is faster than a fresh 'npm install' because we already have them in Prep
        robocopy $PrepNM (Join-Path $WebLoc.SitePath "node_modules") /E /MT:8 /NFL /NDL /NJH /NJS /nc /ns /np
    }

    # --- PHASE 4: AUTO-LAUNCH ---
    # We pass the Gold Master path (SitePath) to the launcher
    if ($WebLoc.AutoLaunch -or $true) { 
        Start-SentinelProduction -SitePath $WebLoc.SitePath
    }

    # Display Final Report
    Write-SentinelReport -Stats $MediaStats -Watch $Global:SentinelTimer  -StartTime $StartTime -RemoteUrl $Global:YamlData.Settings.RemoteUrl
    # --- PHASE 5: MISSION REPORT ---
    $globalStopwatch.Stop()
    
    # FIX: Use the stopwatch's own elapsed time directly
    $Duration = $globalStopwatch.Elapsed.ToString('mm\:ss')
    
    $ErrorColor = if ($MediaStats.Errors -gt 0) { 'Red' } else { 'Gray' }

    Write-Host "`n==============================================================================" -ForegroundColor Gray
    Write-Host " MISSION COMPLETE: $ToolHeader" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Check) Files Scanned: $($MediaStats.Scanned)" -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Arrow) Files Moved:   $($MediaStats.Moved)"   -ForegroundColor Cyan
    Write-Host "  $($Global:Icons.Error) Errors:        $($MediaStats.Errors)"  -ForegroundColor $ErrorColor
    Write-Host "  $($Global:Icons.Check) Total Time:    $Duration"               -ForegroundColor White
    Write-Host "  $($Global:Icons.Check) Remote Access: http://millerjohneric.asuscomm.com:3000" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Gray
}
function Global:Get-SentinelWebLocations {
    param($Locations)
    # Filters locations that have a Website role and a defined SitePath
    return $Locations | Where-Object {
        $_.Role -eq 'Website' -and -not [string]::IsNullOrWhiteSpace($_."'SitePath'")
    }
}

function Global:Invoke-SentinelBranding {
    param([string]$SitePath, [string]$TemplateDir)

    Write-Host "`n$($Global:Icons.Check) Injecting Branding & Configs..." -ForegroundColor Cyan

    # --- SECTION 0: THE SCRUB ---
    # Enhanced to target default Docusaurus icons specifically
    $Junk = @("static/img/logo.svg", "static/img/favicon.ico", "static/favicon.ico")
    foreach ($j in $Junk) {
        $p = Join-Path $SitePath $j
        if (Test-Path $p) { Remove-Item $p -Force }
    }

    # --- SECTION 1: FAVICON DEPLOYMENT ---
    # Look for the-source.ico in your branding folder
    $FavSource = Join-Path $TemplateDir "branding/img/the-source.ico"
    $FavDest = Join-Path $SitePath "static/img/favicon.ico" # Docusaurus expects this name
    
    if (Test-Path $FavSource) {
        Copy-Item $FavSource $FavDest -Force
        Write-Host "  $($Global:Icons.Check) Deployed custom favicon: the-source.ico" -ForegroundColor Gray
    }

    # --- SECTION 2: CONFIG & CORE OVERLAYS ---
    $SrcCfg = Join-Path $TemplateDir 'core-config'
    if (Test-Path $SrcCfg) {
        Get-ChildItem $SrcCfg -Include *.js, *.json, *.yml | Where-Object { $_.Name -ne 'custom.css' -and $_.Name -ne 'index.js' } | Copy-Item -Destination $SitePath -Force

        # Update Global CSS
        $DstCSS = Join-Path $SitePath 'src/css/custom.css'
        if (!(Test-Path (Split-Path $DstCSS))) { New-Item (Split-Path $DstCSS) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'custom.css')) {
            Copy-Item (Join-Path $SrcCfg 'custom.css') $DstCSS -Force
        }

        # Update Homepage Component
        $DstHome = Join-Path $SitePath 'src/pages/index.js'
        if (!(Test-Path (Split-Path $DstHome))) { New-Item (Split-Path $DstHome) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'index.js')) {
            Copy-Item (Join-Path $SrcCfg 'index.js') $DstHome -Force
        }
    }

    # --- SECTION 3: COMPONENT & ASSET SYNC ---
    $SrcComp = Join-Path $TemplateDir 'components'
    $DstComp = Join-Path $SitePath 'src/components'
    if (Test-Path $SrcComp) {
        if (!(Test-Path $DstComp)) { New-Item $DstComp -ItemType Directory -Force | Out-Null }
        Copy-Item (Join-Path $SrcComp '*') $DstComp -Force
    }

    $SrcImg = Join-Path $TemplateDir 'branding/img'
    $DstImg = Join-Path $SitePath 'static/img'
    if (Test-Path $SrcImg) {
        if (!(Test-Path $DstImg)) { New-Item $DstImg -ItemType Directory -Force | Out-Null }
        robocopy "$SrcImg" "$DstImg" /E /R:0 /W:0 /NJH /NJS /NDL /NFL /NC /NS | Out-Null
    }
}

function Global:Remove-SentinelBoilerplate {
    param([string]$SitePath)

    # SAFETY: If SitePath is null or empty, try to recover from global scope
    if ([string]::IsNullOrWhiteSpace($SitePath)) { $SitePath = $Global:TargetWebsitePath }
    if ([string]::IsNullOrWhiteSpace($SitePath)) { return } # Exit if still empty

    Write-Host "  $($Global:Icons.Arrow) Scrubbing Docusaurus boilerplate & caches..." -ForegroundColor Gray

    $DefaultClutter = @(
        "blog",
        "docs/tutorial-basics",
        "docs/tutorial-extras",
        "docs/intro.md",
        "src/pages/index.js",
        "static/img/logo.svg",
        ".docusaurus"
    )

    foreach ($Item in $DefaultClutter) {
        $TargetPath = Join-Path $SitePath $Item
        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Re-create essential directories if they were wiped
    $Dirs = @("docs", "static/img", "src/css")
    foreach ($Dir in $Dirs) {
        $Path = Join-Path $SitePath $Dir
        if (!(Test-Path $Path)) {
            New-Item $Path -ItemType Directory -Force | Out-Null
        }
    }
}

function Global:New-WebPageFromTemplate {
    param(
        [System.IO.FileInfo[]]$SourceFiles,
        [string]$TargetFolder,
        [string[]]$AssetExts,
        [bool]$Overwrite,
        [string]$FolderName,
        [string]$RootType
    )

    # 1. Identify Primary Markdown and Sidecar YAML
    $PrimaryFile = $SourceFiles | Where-Object { $_.Extension -match 'md' } | Select-Object -First 1
    if ($null -eq $PrimaryFile) { $PrimaryFile = $SourceFiles[0] }

    $Sidecar = $SourceFiles | Where-Object { $_.Extension -eq '.yml' -and $_.BaseName -eq $PrimaryFile.BaseName }
    $Data = if ($Sidecar) { Get-Content $Sidecar.FullName -Raw | ConvertFrom-Yaml } else { $null }

    # 2. Extract Title (Forced String Casting to fix Docusaurus [object Object] error)
    [string]$TitleString = ""
    if ($Data.Recipe) { $TitleString = $Data.Recipe.ToString() }
    elseif ($Data.Product) { $TitleString = $Data.Product.ToString() }
    else { $TitleString = $PrimaryFile.BaseName.ToString() }

    # Clean title for YAML: remove existing quotes and wrap in single quotes
    $CleanTitle = $TitleString -replace "['""]", ""
    
    $TargetPath = Join-Path $TargetFolder "$($PrimaryFile.BaseName).mdx"
    if ((Test-Path $TargetPath) -and -not $Overwrite) { return 'SKIPPED' }

    # 3. Process Content
    $RawMD = ""
    if ($PrimaryFile.Extension -match 'md') { $RawMD = Get-Content $PrimaryFile.FullName -Raw }
    $MDContent = Clean-SentinelContent -Content $RawMD

    # 4. Content Generation with Media handling (Preserved Logic)
    $Body = ""
    $MediaGallery = "`n### Media & Assets`n"

    foreach ($file in $SourceFiles) {
        if ($file.FullName -eq $PrimaryFile.FullName -or $file.Extension -eq '.yml') { continue }

        $ext = $file.Extension.ToLower()
        if ($ext -match 'jpg|png|webp|heic') {
            $MediaGallery += "![Asset](./$($file.Name))`n"
        } elseif ($ext -eq '.mp4') {
            $MediaGallery += "#### Video: $($file.Name)`n<video controls width='100%' src={require('./$($file.Name)').default}></video>`n"
        } elseif ($ext -eq '.mp3') {
            $MediaGallery += "#### Audio: $($file.Name)`n<audio controls src={require('./$($file.Name)').default}></audio>`n"
        }
    }

    # 5. Construct Header and Body
    $Header = "---`ntitle: '$CleanTitle'`n---`n`n"

    $ImportHeader = switch ($RootType) {
        'web-culinary' { "import RecipeCard from '@site/src/components/templates/RecipeCard';`n`n" }
        'web-shop'     { "import ProductView from '@site/src/components/templates/ProductView';`n`n" }
        'web-gallery'  { "import Zoom from 'react-medium-image-zoom';`nimport 'react-medium-image-zoom/dist/styles.css';`n`n" }
        Default { "" }
    }

    switch ($RootType) {
        'web-culinary' {
            $Ingreds = ""
            if ($Data.Ingredients) {
                $Ingreds = "### Ingredients`n"
                foreach ($item in $Data.Ingredients) { $Ingreds += "* $item`n" }
            }
            $Body = "<RecipeCard title='$CleanTitle'>`n`n$MDContent`n`n$Ingreds`n</RecipeCard>`n$MediaGallery"
        }
        'web-shop' {
            $Specs = ""
            if ($Data.Details) {
                $Specs = "### Specifications`n"
                $Data.Details.PSObject.Properties | ForEach-Object { $Specs += "* **$($_.Name)**: $($_.Value)`n" }
            }
            $Body = "<ProductView title='$CleanTitle'>`n`n$MDContent`n`n$Specs`n</ProductView>`n$MediaGallery"
        }
        'web-gallery' {
            $Body = "## Gallery: $CleanTitle`n`n"
            foreach ($file in $SourceFiles) {
                if ($file.Extension -match 'jpg|png|webp|heic') {
                    $Body += "<Zoom><img src={require('./$($file.Name)').default} width='300' /></Zoom>`n"
                }
            }
        }
        Default { $Body = $MDContent + $MediaGallery }
    }

    # 6. Final Write
    try {
        ($Header + $ImportHeader + $Body) | Out-File $TargetPath -Encoding UTF8 -Force
        return 'CREATED'
    } catch {
        return 'ERROR'
    }
}

function Global:Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current, $Total, $Time = "")
    
    $Percent = [math]::Round(($Current / $Total) * 100)
    $Progress = "[$Current/$Total] ($Percent%)"
    
    $Msg = "  $($Global:Icons.Arrow) [{0,-4}] {1,-25} {2,-18} [{3}] {4}" -f $Tag, $Source, $Progress, $Time, $Path
    
    # Get console width and pad right to overwrite old characters
    $Width = $Host.UI.RawUI.WindowSize.Width - 1
    if ($Msg.Length -gt $Width) { $Msg = $Msg.Substring(0, $Width) }
    
    Write-Host ("`r" + $Msg.PadRight($Width)) -NoNewline
}

function Global:Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}

function Global:Clear-SentinelContent {
    param([string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return "" }
    $Escaped = $Content -replace '\{', '&#123;' -replace '\}', '&#125;'
    $Escaped = $Escaped -replace '(?m)^:', '\:'
    return $Escaped.Trim()
}

function Global:Write-SentinelReport {
    param(
        $Stats, 
        $Watch, 
        $RemoteUrl
    )
    
    # NULL GUARD: If $Watch is null, fallback to a '00:00' string
    $Duration = "00:00"
    if ($null -ne $Watch) {
        if ($Watch.IsRunning) { $Watch.Stop() }
        $Duration = $Watch.Elapsed.ToString('mm\:ss')
    }
    
    $ErrorColor = if ($Stats.Errors -gt 0) { 'Red' } else { 'Gray' }

    Write-Host "`n==============================================================================" -ForegroundColor Gray
    Write-Host " MISSION COMPLETE: Sentinel Unified Sync" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Check) Files Scanned: $($Stats.Scanned)" -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Arrow) Files Moved:   $($Stats.Moved)"   -ForegroundColor Cyan
    Write-Host "  $($Global:Icons.Error) Errors:        $($Stats.Errors)"  -ForegroundColor $ErrorColor
    Write-Host "  $($Global:Icons.Check) Total Time:    $Duration"               -ForegroundColor White
    Write-Host "  $($Global:Icons.Check) Remote Access: $RemoteUrl"              -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Gray
}

function Global:Write-SentinelCategoryYaml {
    param([string]$Path, [string]$Label)
    $YamlPath = Join-Path $Path '_category_.yml'
    # Updated to strictly use single quotes for keys
    $Content = @"
'label': '$Label'
'link':
  'type': 'generated-index'
"@
    $Content | Out-File $YamlPath -Encoding UTF8 -Force
}

function Global:Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot 'index.md'
    $DirName = Split-Path $TargetRoot -Leaf
    $Content = "---`ntitle: '$DirName'`nsidebar_label: 'Overview'`nslug: '/'`n---`n`nimport DocCardList from '@theme/DocCardList';`n`n# $DirName Gallery`n`n<DocCardList />"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}

function Global:Sync-SentinelWebContent {
    param($Locations, $Settings)

    $TargetWebsitePath = $Settings.SitePath.Replace("'", "")
    
    foreach ($loc in $Locations) {
        if ($loc.Role -ne 'Website') { continue }

        $Source = $loc.Path.Replace("'", "")
        $SubFolder = $loc.WebSubFolder.Replace("'", "")
        
        # MAPPING: Content goes to C:\Source_Studio\website\<WebSubFolder>
        $Destination = Join-Path $TargetWebsitePath $SubFolder

        Write-Host "  $($Global:Icons.Arrow) Mirroring $SubFolder..." -ForegroundColor Gray
        
        # Ensure destination exists
        if (!(Test-Path $Destination)) { New-Item $Destination -ItemType Directory -Force | Out-Null }

        # Execute Robocopy (Mirror mode)
        $RoboArgs = @($Source, $Destination, "*.md", "*.mdx", "*.yml", "*.png", "*.jpg", "/MIR", "/R:0", "/W:0", "/NDL", "/NFL")
        & robocopy @RoboArgs
    }
}

function Global:Format-SentinelNum {
    param([int]$Number)
    return $Number.ToString('#,0')
}

function Global:Get-SentinelRoleColor {
    param([string]$Role)
    # Added Website role color (Green)
    if ($Role -eq 'Website') { return 'Green' }
    if ($Role -match 'Hybrid') { return 'Red' }
    switch -regex ($Role) {
        'Photo'        { return 'Yellow' }
        'RAW'          { return 'Cyan' }
        'Video|Audio'  { return 'Magenta' }
        'Pickup'       { return 'Gray' }
        Default        { return 'White' }
    }
}

function Global:Get-SafeYaml {
    param($v)
    if ($v) { return $v.ToString().Replace("'", "''") } else { return "" }
}

function Global:Get-SafeYamlTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return "Untitled" }

    # Escape double quotes and wrap the whole title in double quotes
    $CleanTitle = $Title -replace '"', '\"'
    return "`"$CleanTitle`""
}

function Global:Get-SentinelBuddy {
    param([System.IO.FileInfo]$Sidecar, [string]$SearchRoot)
    try {
        return Get-ChildItem $SearchRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.BaseName -eq $Sidecar.BaseName -and $_.Extension -ne '.xmp'
        } | Select-Object -First 1
    }
    catch { return $null }
}

function Global:Get-SentinelWebExtensions {
    param($FileTypeData)
    $FinalList = @()
    foreach ($item in $FileTypeData.WebContent) {
        if ($FileTypeData.ContainsKey($item)) { $FinalList += $FileTypeData.$item }
        else { $FinalList += $item }
    }
    return $FinalList | ForEach-Object { $_.ToLower().TrimStart('.') } | Select-Object -Unique
}

function Global:Get-SentinelWidth {
    try { return $Host.UI.RawUI.WindowSize.Width - 5 } catch { return 115 }
}

function Global:Initialize-SentinelSecrets {
    # Reference global data to avoid "not defined" errors
    if ($null -eq $Global:YamlData) {
        Write-Host "  $($Global:Icons.Warning) [WAIT] YAML data not found in Global scope." -ForegroundColor Gray
        return
    }

    $Conf = $Global:YamlData.Settings.EmailSettings
    $SecretFile = Join-Path $PSScriptRoot ($Conf.CredPath)
    $SecretDir = Split-Path $SecretFile

    if (!(Test-Path $SecretDir)) {
        New-Item -Path $SecretDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $SecretFile)) {
        Write-Host "`n$($Global:Icons.Warning) [SECURITY] No credentials found for $($Conf.To)" -ForegroundColor Yellow
        $RawPass = Read-Host "Paste your 16-character GMail App Password"
        $SecPass = ConvertTo-SecureString ($RawPass.Trim()) -AsPlainText -Force
        New-Object System.Management.Automation.PSCredential($Conf.To, $SecPass) | Export-CliXml -Path $SecretFile
    }
}

function Global:Invoke-SentinelPrune {
    param($Locations, $Settings)

    if (-not $Settings.PruneWebsite) { return }

    Write-Host "`nPHASE 4: Pruning Orphaned Sandbox Content..." -ForegroundColor Cyan

    foreach ($loc in $Locations) {
        if ($loc.Role -ne 'Website' -or $loc.RootType -eq 'web-root') { continue }

        $SourceDir = $loc.Path.Replace("'", "")
        $SandboxDir = Join-Path $loc.SitePath.Replace("'", "") $loc.WebSubFolder.Replace("'", "")

        if (Test-Path $SandboxDir) {
            $SandboxFiles = Get-ChildItem $SandboxDir -Recurse -File
            foreach ($File in $SandboxFiles) {
                # Calculate what the source path would be
                $RelativePath = $File.FullName.Replace($SandboxDir, "").TrimStart('\')
                $EquivalentSource = Join-Path $SourceDir $RelativePath

                # Check for MDX vs MD mismatch
                $SourceCheck = $EquivalentSource -replace '\.mdx$', '.md'

                if (!(Test-Path $SourceCheck) -and !(Test-Path $EquivalentSource)) {
                    Write-Host "  $($Global:Icons.Warning) Pruning Orphan: $($File.Name)" -ForegroundColor Yellow
                    Remove-Item $File.FullName -Force
                }
            }
        }
    }
}

function Global:Start-SentinelWebsite {
    param([string]$Path)
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "  $($Global:Icons.Error) Cannot start: Path is null." -ForegroundColor Red
        return
    }

    Set-Location $Path
    
    # Check if we need to install dependencies
    if (!(Test-Path (Join-Path $Path "node_modules"))) {
        Write-Host "`nPHASE 4: Initializing Node Modules (First Run)..." -ForegroundColor Yellow
        Write-Host "  This may take a minute for Source Studio..." -ForegroundColor Gray
        npm install
    }

    Write-Host "`nPHASE 4: Launching Source Studio Engine..." -ForegroundColor Cyan
    npm start
}

function Global:Test-SentinelExclusion {
    param([string]$FullPath)

    # Safety check for empty exclusion list
    $Exclusions = $Global:YamlData.FileTypes.Exclusions
    if ($null -eq $Exclusions) { return $false }

    foreach ($Excl in $Exclusions) {
        # If the exclusion string is found anywhere in the path, skip it
        if ($FullPath.ToLower().Contains($Excl.ToLower())) {
            return $true
        }
    }
    return $false
}

function Global:Initialize-SentinelTemplates {
    param([string]$TemplateDir)

    $Folders = @(
        'branding/img', 'components', 'core-config',
        'content-seeds/docs', 'content-seeds/recipes', 
        'content-seeds/gallery', 'content-seeds/shop'
    )

    # 1. Create Structure
    foreach ($F in $Folders) {
        $Path = Join-Path $TemplateDir $F
        if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force | Out-Null }
    }

    # 2. Define Gold Master Configs (Option 1: index.js added here)
    $Configs = @{
        'core-config/custom.css'           = ":root { --ifm-color-primary: #2e8555; } .navbar { box-shadow: 0 1px 2px 0 rgba(0,0,0,0.1); }"
        'core-config/nav-registry.json'    = '{"lastUpdate": "", "version": "20.16", "entries": []}'
        'core-config/docusaurus.config.js' = "module.exports = { title: 'Source Studio', tagline: 'Sentinel Generated', url: 'http://localhost', baseUrl: '/', presets: [['classic', { docs: { sidebarPath: require.resolve('./sidebars.js') } }]], plugins: [] };"
        
        # This creates the automatic redirect from / to /docs
        'core-config/index.js'             = "import React from 'react';`nimport {Redirect} from '@docusaurus/router';`nexport default function Home() { return <Redirect to='/docs' />; }"
        
        'components/RecipeCard.js'         = "import React from 'react';`nexport default function RecipeCard({children, title}) { return (<div className='recipe-card'><h1>{title}</h1>{children}</div>); }"
        'components/ProductView.js'        = "import React from 'react';`nexport default function ProductView({children, title}) { return (<div className='shop-view'><h2>{title}</h2>{children}</div>); }"
        'components/GalleryView.js'        = "import React from 'react';`nexport default function GalleryView({children}) { return (<div className='gallery-grid' style={{display:'flex', flexWrap:'wrap', gap:'10px'}}>{children}</div>); }"
    }

    # 3. Critical Verification (Logo only)
    $LogoPath = Join-Path $TemplateDir 'branding/img/logo.svg'
    if (!(Test-Path $LogoPath)) {
        "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><circle cx='50' cy='50' r='40' fill='green'/></svg>" | Out-File $LogoPath -Encoding UTF8
    }

    # 4. Write all missing Configs
    foreach ($Key in $Configs.Keys) {
        $FilePath = Join-Path $TemplateDir $Key
        if (!(Test-Path $FilePath)) {
            Write-Host "  $($Global:Icons.Check) Restoring: $Key" -ForegroundColor Gray
            $Configs[$Key] | Out-File $FilePath -Encoding UTF8 -Force
        }
    }
    Write-Host "  $($Global:Icons.Check) Template Initialization Complete." -ForegroundColor Green
}

function Global:Invoke-SentinelRecipeContent {
    param(
        [string]$SourceDataDir, 
        [string]$TargetDir, 
        [string]$TemplatePath,
        [string]$GroupSeparator = '-.-' # Default if not specified
    )

    if (!(Test-Path $TargetDir)) { 
        New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null 
    }

    if (!(Test-Path $TemplatePath)) {
        Write-Host "  $($Global:Icons.Error) Template missing: $TemplatePath" -ForegroundColor Red
        return
    }

    $RawTemplate = Get-Content $TemplatePath -Raw
    $Files = Get-ChildItem $SourceDataDir -File | Where-Object { $_.Name -ne 'index.md' -and $_.Name -ne '_category_.yml' }
    
    if ($Files.Count -eq 0) { return }

    # Grouping Logic: If separator is empty or not found, every file is its own group (Photography style)
    $GroupedItems = $Files | Group-Object { 
        if ($GroupSeparator -and $_.Name -contains $GroupSeparator) { 
            $_.BaseName.Split($GroupSeparator)[0] 
        } else { 
            $_.BaseName 
        }
    }

    foreach ($Group in $GroupedItems) {
        $ItemName = $Group.Name
        $MarkdownFile = Join-Path $TargetDir "$ItemName.md"
        $Content = $RawTemplate

        # 1. Asset Discovery
        $ImageFiles = $Group.Group | Where-Object { $_.Extension -match 'jpg|png|svg|jpeg' }
        $YamlImageList = ""
        $PrimaryImage = ""

        if ($ImageFiles) {
            $PrimaryImage = $ImageFiles[0].Name
            foreach ($Img in $ImageFiles) {
                $YamlImageList += "  - '$($Img.Name)'`r`n"
            }
        }

        # 2. Map Placeholders (Handling the 'styled_body' crash)
        $Content = $Content -replace '\{\{title\}\}', $ItemName
        $Content = $Content -replace '\{\{slug\}\}', $ItemName
        $Content = $Content -replace '\{\{primary_image_url\}\}', $PrimaryImage
        $Content = $Content -replace '\{\{images_list\}\}', $YamlImageList.TrimEnd()
        
        # This prevents the "styled_body is not defined" error in Docusaurus
        $Content = $Content -replace '\{\{styled_body\}\}', "Media archive for $ItemName"

        # 3. Write File
        $Content | Out-File $MarkdownFile -Encoding UTF8 -Force
        Write-Host "  $($Global:Icons.Check) Generated Card: $($ItemName).md" -ForegroundColor Gray
    }
}

function Global:Send-SentinelNotification {
    param(
        [string]$SiteName,
        [string]$Status,
        [int]$TotalGroups,
        [int]$NewPages,
        [int]$Preserved,
        [string]$MirrorTarget,
        [string]$SiteUrl
    )

    $Email = $script:YamlData.Settings.EmailSettings
    $CredPath = Join-Path $PSScriptRoot $Email.CredPath

    if (!(Test-Path $CredPath)) { return }

    try {
        $Cred = Import-CliXml -Path $CredPath
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        
        # Exact Template Formatting
        $Body = @"
Sentinel Sync: $SiteName
---------------------------------------
Current Site Status:  $Status
Total Groups:         $TotalGroups
NEW Pages Created:    $NewPages
EXISTING (Preserved): $Preserved
---------------------------------------
Mirror Target:        $MirrorTarget
Live Site Updated:
$SiteUrl/$SiteName
"@

        Send-MailMessage `
            -To $Email.To `
            -From $Email.To `
            -Subject "Sentinel $SiteName Report: $Timestamp" `
            -Body $Body `
            -SmtpServer 'smtp.gmail.com' `
            -Port 587 `
            -UseSsl `
            -Credential $Cred
            
        Write-Host "  $($Global:Icons.Check) Mission Report Sent for $SiteName" -ForegroundColor Gray
    }
    catch {
        Write-Host "  $($Global:Icons.Error) SMTP Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Global:Write-SentinelDocusaurusConfig {
    param([string]$SitePath, $YamlData)

    $ConfigPath = Join-Path $SitePath "docusaurus.config.js"
    
    # Validation Logic: Ensure we have a title
    $SiteName = $YamlData.Settings.SiteName
    if ([string]::IsNullOrWhiteSpace($SiteName)) { 
        $SiteName = "Sentinel Wiki" 
        Write-Host "  $($Global:Icons.Warning) No SiteName found in YAML, using default." -ForegroundColor Yellow
    }

    $ConfigContent = @"
const config = {
  title: '$SiteName',
  tagline: 'Sentinel Automated Wiki',
  url: 'http://millerjohneric.asuscomm.com',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',
  favicon: 'img/favicon.ico',

  presets: [
    [
      'classic',
      ({
        docs: {
          sidebarPath: require.resolve('./sidebars.js'),
        },
        blog: {
          showReadingTime: true,
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig: ({
    navbar: {
      title: '$SiteName',
      items: [
        {type: 'docSidebar', sidebarId: 'tutorialSidebar', position: 'left', label: 'Knowledge Base'},
        {to: '/blog', label: 'Blog', position: 'left'},
      ],
    },
  }),
};

module.exports = config;
"@

    $ConfigContent | Out-File -FilePath $ConfigPath -Encoding utf8
    Write-Host "  $($Global:Icons.Check) Dynamic config updated: Site Title set to '$SiteName'." -ForegroundColor Gray
}

function Global:Get-SentinelRevision {
    param([string]$ScriptPath)
    $VersionFile = Join-Path $ScriptPath ".sentinel_version"
    $BaseVersion = "20" # Your current major version
    
    if (Test-Path $VersionFile) {
        $Rev = [int](Get-Content $VersionFile) + 1
    } else {
        $Rev = 1
    }
    
    $Rev | Out-File $VersionFile -Encoding utf8
    return "v$BaseVersion.$Rev"
}

function Global:Write-SentinelPhase0 {
    param($YamlData)
    $Locs = if ($YamlData.Locations) { $YamlData.Locations } else { $YamlData.locations }
    
    $MaxName = ($Locs.Name | Measure-Object -Property Length -Maximum).Maximum + 2
    $MaxRole = ($Locs.Role | Measure-Object -Property Length -Maximum).Maximum + 2
    if ($MaxName -lt 15) { $MaxName = 15 }

    # FIX: Define the string first, then write it with the color
    $HeaderText = "     {0,-10} {1,-$MaxName} {2,-$MaxRole} {3}" -f "STATUS", "NAME", "ROLE", "PATH"
    Write-Host $HeaderText -ForegroundColor Gray

    foreach ($loc in $Locs) {
        $Status = "ACTIVE"; $Color = "White"
        switch -Regex ($loc.Role) {
            "Website"         { $Status = "TARGET"; $Color = "Yellow" }
            "Pickup"          { $Color = "Green" }
            "Archive"         { $Color = "Gray" }
            "InPlace_Archive" { $Color = "Magenta" }
            "timeline"        { $Color = "Cyan" }
        }
        if (!(Test-Path $loc.Path)) { $Status = "OFFLINE"; $Color = "Red" }
        
        $RowText = "     [{0,-8}] [{1,-$MaxName}] [{2,-$MaxRole}] {3}" -f $Status, $loc.Name, $loc.Role, $loc.Path
        Write-Host $RowText -ForegroundColor $Color
    }
}

function Global:Invoke-SentinelWebPipeline {
    param(
        $loc,
        $TemplateDir,
        $TargetWebsitePath
    )

    # 1. Extract the template type from the bracketed string (e.g., [RECIPES])
    if ($loc.Template -match '\[(?<Type>.*?)\](?<File>.*)') {
        $TemplateType = $Matches['Type']
        $TemplateName = $Matches['File']
    } else {
        Write-Host "    $($Global:Icons.Warning) Invalid Template format for $($loc.Name): $($loc.Template)" -ForegroundColor Yellow
        return
    }

    # 2. Define the output path inside the staging /docs folder
    $CleanName = $loc.Name.Replace(' ', '-').ToLower()
    $OutputPath = Join-Path $TargetWebsitePath "docs\$CleanName"

    # 3. Route based on the [TYPE]
    switch ($TemplateType) {
        "SHOP" { 
            Sync-SentinelShop -Source $loc.Path -Output $OutputPath -TemplateDir $TemplateDir 
        }
        "RECIPES" { 
            Sync-SentinelRecipes -Source $loc.Path -Output $OutputPath -TemplateDir $TemplateDir 
        }
        "GALLERY" {
            # Placeholder for jems-tones/photography logic
            Write-Host "    $($Global:Icons.Check) Gallery Pipeline triggered for $TemplateName" -ForegroundColor Gray
        }
        Default {
            Write-Host "    $($Global:Icons.Warning) Unknown Template Type: $TemplateType" -ForegroundColor Yellow
        }
    }
}

function Global:Write-SentinelSidebars {
    param([string]$SitePath)

    $DocsPath = Join-Path $SitePath "docs"
    if (!(Test-Path $DocsPath)) { return }

    Write-Host "  $($Global:Icons.Check) Dynamically generating sidebars.js..." -ForegroundColor Cyan

    # 1. Get all top-level directories in /docs (these are your modules)
    $Modules = Get-ChildItem -Path $DocsPath -Directory

    $SidebarLines = @()
    $SidebarLines += "module.exports = {"
    $SidebarLines += "  tutorialSidebar: ["

    foreach ($M in $Modules) {
        $ModuleName = $M.Name
        # Convert folder name to a readable Label (e.g., culinary-cuisine -> Culinary Cuisine)
        $Label = (Get-Culture).TextInfo.ToTitleCase($ModuleName.Replace("-", " "))
        
        $SidebarLines += "    {"
        $SidebarLines += "      type: 'category',"
        $SidebarLines += "      label: '$Label',"
        $SidebarLines += "      items: ["
        
        # Check if an index.md exists in this module
        if (Test-Path (Join-Path $M.FullName "index.md")) {
            # Use the full relative path as the ID (e.g., 'culinary-cuisine/index')
            $SidebarLines += "        '$ModuleName/index',"
        }

        # Add autogenerated logic for the rest of the folder
        $SidebarLines += "        {"
        $SidebarLines += "          type: 'autogenerated',"
        $SidebarLines += "          dirName: '$ModuleName',"
        $SidebarLines += "        },"
        $SidebarLines += "      ],"
        $SidebarLines += "    },"
    }

    $SidebarLines += "  ],"
    $SidebarLines += "};"

    # 2. Join and Write (Using single quotes for keys where possible)
    $FinalJS = $SidebarLines -join "`n"
    $SidebarFile = Join-Path $SitePath "sidebars.js"
    $FinalJS | Out-File -FilePath $SidebarFile -Encoding utf8 -Force
}

function Global:Install-SentinelFramework {
    param(
        [string]$TargetDir
    )

    if ([string]::IsNullOrWhiteSpace($TargetDir) -or $TargetDir -eq 'False') {
        Write-Host "  $($Global:Icons.Error) SitePath invalid in config!" -ForegroundColor Red
        return
    }

    $PackagePath = Join-Path $TargetDir 'package.json'
    
    if (!(Test-Path $PackagePath)) {
        Write-Host "`n$($Global:Icons.Arrow) Engine Missing. Executing Automated JS Scaffold..." -ForegroundColor Yellow
        
        # 1. Setup Staging
        $Parent = Split-Path $TargetDir
        $TempPath = Join-Path $Parent "sentinel_scaffold_tmp"
        if (Test-Path $TempPath) { Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $TempPath -Force | Out-Null

        Push-Location $TempPath
        try {
            # 2. THE COMMAND: Using --javascript explicitly to bypass the prompt
            # Scaffolding into 'staged_engine' inside the temp folder
            npx --yes create-docusaurus@latest staged_engine classic --skip-install --javascript
            
            # 3. TELEPORT: Move contents to the real TargetDir
            if (!(Test-Path $TargetDir)) { New-Item $TargetDir -ItemType Directory -Force | Out-Null }
            Write-Host "  $($Global:Icons.Arrow) Deploying JS Engine to: $TargetDir" -ForegroundColor Gray
            Copy-Item -Path "staged_engine\*" -Destination $TargetDir -Recurse -Force
        } finally {
            Pop-Location
            Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 4. THE PURGE
    Write-Host "  $($Global:Icons.Check) Purging Docusaurus boilerplate..." -ForegroundColor Gray
    $Guts = @('docs', 'blog', 'static/img')
    foreach ($folder in $Guts) {
        $path = Join-Path $TargetDir $folder
        if (Test-Path $path) { 
            Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue 
        }
    }
}

function Global:Write-SentinelHomepageRedirect {
    param([string]$SitePath)
    
    $PagesDir = Join-Path $SitePath "src/pages"
    if (!(Test-Path $PagesDir)) { New-Item $PagesDir -ItemType Directory -Force | Out-Null }
    
    $IndexJs = Join-Path $PagesDir "index.js"
    $Content = @"
import React from 'react';
import {Redirect} from '@docusaurus/router';

export default function Home() {
  return <Redirect to="/docs/index" />;
};
"@
    $Content | Out-File $IndexJs -Encoding UTF8 -Force
    Write-Host "  $($Global:Icons.Check) Homepage redirect created at src/pages/index.js" -ForegroundColor Gray
}

function Global:Write-SentinelXmlTree {
    param([string]$SitePath)

    if ([string]::IsNullOrWhiteSpace($SitePath)) { return }
    $OutputFile = Join-Path $SitePath 'tree.xml'

    function Get-XmlNode {
        param($Item)
        # Proper XML escaping for names
        $Name = $Item.Name.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
        
        if ($Item.PSIsContainer) {
            $xmlStr = "<Directory name='$Name'>"
            $Children = Get-ChildItem -Path $Item.FullName | Where-Object { $_.FullName -notmatch '\\(node_modules|\.docusaurus|\.git)' }
            foreach ($Child in $Children) {
                $xmlStr += Get-XmlNode -Item $Child
            }
            $xmlStr += "</Directory>"
        }
        else {
            $xmlStr = "<File name='$Name' />"
        }
        return $xmlStr
    }

    if (Test-Path $SitePath) {
        $RootName = (Get-Item $SitePath).Name
        $RawXml = "<?xml version='1.0' encoding='UTF-8'?><Project name='$RootName'>"
        $TopLevelItems = Get-ChildItem -Path $SitePath | Where-Object { $_.FullName -notmatch '\\(node_modules|\.docusaurus|\.git)' }

        foreach ($Item in $TopLevelItems) {
            $RawXml += Get-XmlNode -Item $Item
        }
        $RawXml += "</Project>"

        try {
            # This block 'prettifies' the XML with indentation and new lines
            $Doc = [System.Xml.Linq.XDocument]::Parse($RawXml)
            $Doc.Save($OutputFile)
            Write-Host "  $($Global:Icons.Check) Prettified XML tree refreshed: tree.xml" -ForegroundColor Gray
        }
        catch {
            $RawXml | Out-File -FilePath $OutputFile -Encoding utf8
            Write-Host "  $($Global:Icons.Warning) XML saved without formatting (Parse Error)." -ForegroundColor Yellow
        }
    }
}


function Global:Start-SentinelProduction {
    param([string]$SitePath)

    if ([string]::IsNullOrWhiteSpace($SitePath)) { return }

    Write-Host "`nPHASE 4: Launching Source Studio Engine..." -ForegroundColor Cyan

    # 1. Check for node_modules (The Engine's Heart)
    if (!(Test-Path (Join-Path $SitePath "node_modules"))) {
        Write-Host "  $($Global:Icons.Warning) Dependencies missing in Production. Installing..." -ForegroundColor Yellow
        Push-Location $SitePath
        # Use --no-audit to keep it fast
        npm install --no-audit --no-fund
        Pop-Location
    }

    # 2. Safety Cleanup
    Stop-Process -Name 'node' -ErrorAction SilentlyContinue

    # 3. Execution via NPM
    # Running 'npm start' automatically finds the local docusaurus install
    $StartCommand = "Set-Location '$SitePath'; `$host.UI.RawUI.WindowTitle = 'Sentinel Engine'; npm start -- --host 0.0.0.0"
    
    try {
        Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', $StartCommand -WorkingDirectory $SitePath
        Write-Host "  $($Global:Icons.Check) Engine spawned successfully." -ForegroundColor Gray
    } catch {
        Write-Host "  $($Global:Icons.Error) Failed to launch: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Global:Sync-SentinelShop {
    param($Source, $Output, $TemplateDir)

    Write-Host "`n  $($Global:Icons.Arrow) Processing Pipeline: Millermade Handcrafted" -ForegroundColor Cyan
    Write-Host "    $($Global:Icons.Arrow) Pipeline Path: $Output" -ForegroundColor DarkGray

    # 1. Load the Template
    $TemplateFile = Join-Path $TemplateDir "core-config\shop-item.md"
    if (!(Test-Path $TemplateFile)) {
        Write-Host "    $($Global:Icons.Error) Template missing: $TemplateFile" -ForegroundColor Red
        return
    }
    $TemplateContent = Get-Content $TemplateFile -Raw

    # 2. Get Inventory Items
    $InventoryItems = Get-ChildItem -Path $Source -Filter *.yml
    
    foreach ($Item in $InventoryItems) {
        # Load YAML Data
        $YamlRaw = Get-Content $Item.FullName -Raw
        $Data = $YamlRaw | ConvertFrom-Yaml
        
        $FinalContent = $TemplateContent

        if ($null -ne $FinalContent) {
            # --- STRING ENFORCEMENT LAYER ---
            # We must ensure the Product/Title is a simple string, not a PSObject
            [string]$RawTitle = if ($Data.Product) { $Data.Product } else { $Item.BaseName }
            
            # Clean title: Remove quotes and trim to prevent YAML validation errors
            $CleanTitle = $RawTitle.Trim() -replace "['""]", ""

            # Replace the Primary Title Tags
            $FinalContent = $FinalContent.Replace("{{Product}}", $CleanTitle)
            $FinalContent = $FinalContent.Replace("{{title}}", $CleanTitle)

            # 3. Map all other YAML properties
            foreach ($Prop in $Data.PSObject.Properties) {
                $Key = $Prop.Name
                # Explicitly cast value to string to prevent [object Object] leaks
                [string]$Val = if ($null -ne $Prop.Value) { $Prop.Value } else { "" }
                
                # Double-check: If PowerShell still tries to pass an object, force a trim
                if ($Val -like "*System.Collections*") { $Val = "Data Error" }
                
                $FinalContent = $FinalContent.Replace("{{$Key}}", $Val)
            }

            # 4. Handle Stock Logic
            [string]$StatusText = "OUT OF STOCK"
            if ($null -ne $Data.Stock -and [int]$Data.Stock -gt 0) {
                $StatusText = "IN STOCK"
            }
            $FinalContent = $FinalContent.Replace("{{Status}}", $StatusText)

            # 5. Write the File
            if (!(Test-Path $Output)) { New-Item -ItemType Directory -Path $Output -Force | Out-Null }
            
            $TargetPath = Join-Path $Output "$($Item.BaseName).md"
            $FinalContent | Out-File -FilePath $TargetPath -Encoding utf8 -Force
            
            Write-Host "    $($Global:Icons.Check) Shop Item Generated: $($Item.BaseName)" -ForegroundColor Gray
        }
    }
}

function Global:Sync-SentinelMedia {
    param($Locations, $TargetWebsitePath, $Settings)
    $Stats = @{ Scanned = 0; Moved = 0; Errors = 0 }

    if ([string]::IsNullOrWhiteSpace($TargetWebsitePath)) {
        $WebRootLoc = $Locations | Where-Object { $_.RootType -eq 'web-root' } | Select-Object -First 1
        $TargetWebsitePath = $WebRootLoc.Path
    }

    foreach ($Loc in $Locations) {
        # Only process Website modules; Skip the root itself
        if ($Loc.Role -ne 'Website' -or $Loc.RootType -eq 'web-root') { continue }

        # Ensure we are targeting the 'docs' folder specifically
        $CleanBase = $TargetWebsitePath.TrimEnd('\')
        if ($CleanBase -notlike "*\docs") {
            $CleanBase = Join-Path $CleanBase "docs"
        }

        # Handle the SubFolder (remove 'docs/' if the user put it in YAML)
        $Sub = $Loc.WebSubFolder.Replace("docs/", "").Replace("docs\", "").TrimStart('\')
        $GroupTarget = Join-Path $CleanBase $Sub

        Write-Host "`n  $($Global:Icons.Arrow) Syncing Module: $($Loc.Name)" -ForegroundColor Gray
        
        if (!(Test-Path $GroupTarget)) { New-Item $GroupTarget -ItemType Directory -Force | Out-Null }

        $Files = Get-ChildItem -Path $Loc.Path -Recurse -File
        $TotalFiles = $Files.Count
        $CurrentCount = 0
        
        foreach ($File in $Files) {
            $Stats.Scanned++
            $CurrentCount++

            $BaseSource = $Loc.Path.TrimEnd('\')
            $RelativePath = $File.FullName.Replace($BaseSource, "").TrimStart('\')
            $DestinationPath = Join-Path $GroupTarget $RelativePath

            # Ensure sub-directory exists
            $DestDir = Split-Path $DestinationPath
            if (!(Test-Path $DestDir)) { New-Item $DestDir -ItemType Directory -Force | Out-Null }

            try {
                if ($Settings.GlobalOverwrite -or !(Test-Path $DestinationPath)) {
                    Copy-Item -Path $File.FullName -Destination $DestinationPath -Force
                    $Stats.Moved++
                }
                
                # Odometer for progress
                Write-SentinelOdometer -Tag "COPY" -Source $Loc.Name -Path $File.Name -Current $CurrentCount -Total $TotalFiles
                
            } catch {
                Write-Host ""
                Write-Host "    $($Global:Icons.Error) Failed: $($File.Name)" -ForegroundColor Red
                $Stats.Errors++
            }
        }
        Write-Host "" 
    }
    return $Stats
}

function Export-SentinelArchive {
    $ArchiveDir = Join-Path $PSScriptRoot "_archive"
    if (!(Test-Path $ArchiveDir)) { New-Item $ArchiveDir -ItemType Directory }
    
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
    $ArchiveName = "Sentinel-Core-v21.0-$Timestamp.ps1"
    
    Copy-Item -Path $PSCommandPath -Destination (Join-Path $ArchiveDir $ArchiveName)
    Write-Host "Snapshot archived to $ArchiveDir\$ArchiveName" -ForegroundColor Green
}


# --- AUTO-RUN TRIGGER ---
if ($MyInvocation.MyCommand.Name -eq (Split-Path $PSCommandPath -Leaf) -or $null -eq $MyInvocation.Referrer) {
    Start-SentinelSync
}
