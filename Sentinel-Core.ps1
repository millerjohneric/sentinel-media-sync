# ==============================================================================
# Sentinel Core Library [UPDATED FOR KEYLESS SYNC]
# ==============================================================================

$Global:Icons = @{
    'Arrow'   = [char]0x2192
    'Check'   = [char]0x2714
    'Warning' = [char]0x26A0
    'Error'   = [char]0x2718
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
    $Junk = @("static/img/logo.svg", "static/img/favicon.ico", "static/favicon.ico")
    foreach ($j in $Junk) {
        $p = Join-Path $SitePath $j
        if (Test-Path $p) { Remove-Item $p -Force }
    }
    # 1. Config & Core Overlays (docusaurus.config.js, sidebars.js, nav-registry.json)
    $SrcCfg = Join-Path $TemplateDir 'core-config'
    if (Test-Path $SrcCfg) {
        Get-ChildItem $SrcCfg -Include *.js, *.json, *.yml | Where-Object { $_.Name -ne 'custom.css' -and $_.Name -ne 'index.js' } | Copy-Item -Destination $SitePath -Force

        # A. Update Global CSS
        $DstCSS = Join-Path $SitePath 'src/css/custom.css'
        if (!(Test-Path (Split-Path $DstCSS))) { New-Item (Split-Path $DstCSS) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'custom.css')) {
            Copy-Item (Join-Path $SrcCfg 'custom.css') $DstCSS -Force
        }

        # B. Update Homepage Component
        $DstHome = Join-Path $SitePath 'src/pages/index.js'
        if (!(Test-Path (Split-Path $DstHome))) { New-Item (Split-Path $DstHome) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'index.js')) {
            Copy-Item (Join-Path $SrcCfg 'index.js') $DstHome -Force
        }
    }

    # 2. Component Distribution
    $SrcComp = Join-Path $TemplateDir 'components'
    $DstComp = Join-Path $SitePath 'src/components'
    if (Test-Path $SrcComp) {
        if (!(Test-Path $DstComp)) { New-Item $DstComp -ItemType Directory -Force | Out-Null }
        Copy-Item (Join-Path $SrcComp '*') $DstComp -Force
    }

    # 3. Branding Assets (Images & Icons)
    # This ensures the-source.ico and your custom logo are the only ones standing
    $SrcImg = Join-Path $TemplateDir 'branding/img'
    $DstImg = Join-Path $SitePath 'static/img'
    if (Test-Path $SrcImg) {
        if (!(Test-Path $DstImg)) { New-Item $DstImg -ItemType Directory -Force | Out-Null }
        # robocopy /MIR would wipe the folder, but we use /E to merge and overwrite
        robocopy "$SrcImg" "$DstImg" /E /R:0 /W:0 /NJH /NJS /NDL /NFL /NC /NS | Out-Null
    }

    # 4. Content Seed Population
    $SrcSeeds = Join-Path $TemplateDir 'content-seeds'
    if (Test-Path $SrcSeeds) {
        Write-Host "  $($Global:Icons.Check) Populating content seeds..." -ForegroundColor Gray
        
        # This part handles the specific intro/index file mapping
        Get-ChildItem (Join-Path $SrcSeeds 'docs') -Filter "index - *.md" -ErrorAction SilentlyContinue | ForEach-Object {
            $InstanceID = ($_.BaseName -replace 'index - ', '').Trim()
            $TargetDir = Join-Path $SitePath $InstanceID
            
            if (Test-Path $TargetDir) {
                Copy-Item $_.FullName (Join-Path $TargetDir 'index.md') -Force
            }
        }
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

function Global:Initialize-SentinelWebRoot {
    param(
        [string]$BuildPath, 
        [string]$DeployPath,
        $EngineLoc
    )

    # Clean trailing slashes for robust path joining
    $BuildPath = $BuildPath.TrimEnd('\')
    $DeployPath = $DeployPath.TrimEnd('\')
    
    # --- STEP 1: BUILD/SCAFFOLD AT SOURCE PATH ---
    if (!(Test-Path (Join-Path $BuildPath 'package.json'))) {
        Write-Host "  $($Global:Icons.Warning) Engine missing at $BuildPath. Scaffolding..." -ForegroundColor Yellow
        # Existing npx create-docusaurus logic goes here targeting $BuildPath
    }

    # --- STEP 2: DEPLOY TO SITEPATH ---
    # We mirror the BuildPath to the SitePath, excluding heavy/generated folders
    if ($BuildPath -ne $DeployPath) {
        Write-Host "  $($Global:Icons.Arrow) Deploying Build to Production: $DeployPath" -ForegroundColor Gray
        if (!(Test-Path $DeployPath)) { New-Item $DeployPath -ItemType Directory -Force | Out-Null }
        
        # /MIR ensures SitePath is an exact replica of the Build Path
        # /XD excludes node_modules so we don't waste time copying thousands of small files
        $RoboArgs = @("$BuildPath", "$DeployPath", "/MIR", "/XD", "node_modules", ".git", ".docusaurus", "/R:0", "/W:0", "/NFL", "/NDL", "/NJH", "/NJS")
        robocopy @RoboArgs | Out-Null
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

function Global:Sync-SentinelMedia {
    param($Locations, $Settings)
    
    $Stats = @{ 'Scanned' = 0; 'Moved' = 0; 'Errors' = 0 }
    
    # Identify the Target Anchor
    $WebRoot = $Locations | Where-Object { $_.RootType -eq 'web-root' }
    $SiteRoot = $WebRoot.SitePath
    $DocsPath = Join-Path $SiteRoot 'docs'

    foreach ($Loc in $Locations) {
        # SKIP: The target engine itself and the timeline archive
        if ($Loc.RootType -eq 'web-root' -or $Loc.Name -eq 'timeline') { continue }
        
        # LOGIC: Adjacent for specialty websites, Nested for pickups
        if ($Loc.Role -eq 'Website') {
            # Syncs adjacent to docs: C:\Source_Studio\website\millermade-handcrafted
            $GroupTarget = Join-Path $SiteRoot $Loc.Name
        } elseif ($Loc.Role -eq 'Pickup') {
            # Syncs inside docs: C:\Source_Studio\website\docs\Roena
            $GroupTarget = Join-Path $DocsPath $Loc.Name
        } else {
            # Skip non-web/non-pickup roles
            continue 
        }
        
        Write-Host "  $($Global:Icons.Arrow) Syncing Module: $($Loc.Name)" -ForegroundColor Gray
        if (!(Test-Path $GroupTarget)) { New-Item $GroupTarget -ItemType Directory -Force | Out-Null }

        $Files = Get-ChildItem -Path $Loc.Path -Recurse -File
        foreach ($File in $Files) {
            # SILENT INVISIBLE INTERRUPT: Polling hardware buffer
            if ([System.Console]::KeyAvailable) { return $Stats }

            $Stats.Scanned++
            if (Test-SentinelExclusion -FullPath $File.FullName) { continue }

            try {
                $DestinationPath = Join-Path $GroupTarget $File.Name
                if ($Settings.GlobalOverwrite -or !(Test-Path $DestinationPath)) {
                    # Yield slightly to allow Ctrl+C to propagate
                    Start-Sleep -Milliseconds 1 
                    Copy-Item -Path $File.FullName -Destination $DestinationPath -Force
                    $Stats.Moved++
                }
            } catch {
                $Stats.Errors++
            }
        }
    }
    return $Stats
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
    param($loc, $Settings, $TargetWebsitePath)

    # 1. Parse '[MODE]filename' - Hardened Regex
    if ($loc.Template -match '^\[(?<Mode>[^\]]+)\](?<File>.*)') {
        $RawMode = $Matches['Mode'].ToLower().Trim()
        $TemplateName = $Matches['File'].Trim()
    } else {
        Write-Host "  $($Global:Icons.Error) Invalid Template Format: $($loc.Template)" -ForegroundColor Red
        return
    }

    # 2. Construct Template Path
    $TemplateDir = $Settings.TemplateDir.TrimEnd('\')
    # This ensures we get ...\templates\content-seeds\shop\hand-crafted.md
    $TargetTemplateFile = Join-Path $TemplateDir "content-seeds\$RawMode\$TemplateName.md"

    # 3. Resolve Processing Paths
    $SubFolder = $loc.WebSubFolder
    $SourceData = Join-Path $TargetWebsitePath $SubFolder
    $OutputDir = Join-Path $TargetWebsitePath "docs\$SubFolder"

    if (!(Test-Path $OutputDir)) { New-Item $OutputDir -ItemType Directory -Force | Out-Null }

    # 4. DYNAMIC EXECUTION
    $TextInfo = (Get-Culture).TextInfo
    $CleanMode = $TextInfo.ToTitleCase($RawMode.ToLower())
    $CmdName = "Sync-Sentinel$CleanMode"

    if (Get-Command $CmdName -ErrorAction SilentlyContinue) {
        $Splat = @{
            Source       = $SourceData
            Output       = $OutputDir
            TemplatePath = $TargetTemplateFile
        }
        & $CmdName @Splat
    } else {
        Write-Host "  $($Global:Icons.Warning) No function found for: $CmdName" -ForegroundColor Yellow
    }
}


function Global:Sync-SentinelRecipes {
    param($Source, $Output, $TemplatePath)

    # Safer template loading pattern
    $TemplateContent = Get-Content -Path $TemplatePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $TemplateContent) { $TemplateContent = (Get-Content -Path $TemplatePath) -join "`r`n" }

    if ($null -eq $TemplateContent) {
        Write-Host "    $($Global:Icons.Error) Template is empty or missing: $TemplatePath" -ForegroundColor Red
        return
    }
    $RecipeFiles = Get-ChildItem -Path $Source -Filter "*.yml" -Recurse
    foreach ($File in $RecipeFiles) {
        try {
            # Load YAML data (Assumes ConvertFrom-Yaml is in your Core)
            $RecipeData = Get-Content $File.FullName -Raw | ConvertFrom-Yaml
            $Slug = $File.BaseName
            $FinalContent = $TemplateContent

            # Variable Injection: Replaces {{Key}} with YAML value
            foreach ($Prop in $RecipeData.PSObject.Properties) {
                $Key = $Prop.Name
                $Value = $Prop.Value
                $FinalContent = $FinalContent.Replace("{{$Key}}", [string]$Value)
            }

            # Write the Docusaurus Card
            $TargetPath = Join-Path $Output "$Slug.md"
            $FinalContent | Out-File -FilePath $TargetPath -Encoding utf8
            Write-Host "    $($Global:Icons.Check) Generated Card: $Slug.md" -ForegroundColor Gray
        }
        catch {
            Write-Host "    $($Global:Icons.Error) Failed: $($File.Name)" -ForegroundColor Red
        }
    }
}
functifunction Global:Sync-SentinelMedia {
    param($Locations, $Settings)
    
    $Stats = @{ 'Scanned' = 0; 'Moved' = 0; 'Errors' = 0 }
    
    # Identify the Website root for deployment
    $WebRoot = $Locations | Where-Object { $_.RootType -eq 'web-root' }
    $TargetBase = Join-Path $WebRoot.SitePath "docs"

    foreach ($Loc in $Locations) {
        # Skip the engine itself and non-plugin roles
        if ($Loc.Role -eq 'Website' -or $Loc.RootType -eq 'web-root') { continue }
        
        Write-Host "  $($Global:Icons.Arrow) Syncing Group: $($Loc.Name)" -ForegroundColor Gray
        
        # Ensure the sub-folder exists in the docs directory
        $GroupName = $Loc.Name
        $GroupTarget = Join-Path $TargetBase $GroupName
        
        if (!(Test-Path $GroupTarget)) { 
            New-Item $GroupTarget -ItemType Directory -Force | Out-Null 
        }

        $Files = Get-ChildItem -Path $Loc.Path -Recurse -File
        foreach ($File in $Files) {
            $Stats.Scanned++
            
            if (Test-SentinelExclusion -FullPath $File.FullName) { continue }

            # Logic for moving/copying files to $GroupTarget goes here
            # $Stats.Moved++
        }
    }
    return $Stats
}on Global:Sync-SentinelMedia {
    param($Locations, $Settings)
    
    $Stats = @{ 'Scanned' = 0; 'Moved' = 0; 'Errors' = 0 }
    
    foreach ($Loc in $Locations) {
        if ($Loc.Role -eq 'Website') { continue }
        
        Write-Host "  $($Global:Icons.Arrow) Syncing Group: $($Loc.Name)" -ForegroundColor Gray
        
        $Files = Get-ChildItem -Path $Loc.Path -Recurse -File
        foreach ($File in $Files) {
            $Stats.Scanned++
            
            # Unified File/Folder Exclusion Check
            if (Test-SentinelExclusion -FullPath $File.FullName) {
                continue 
            }
        }
        $GroupTarget = Join-Path $TargetBase $GroupName
        if (!(Test-Path $GroupTarget)) { New-Item $GroupTarget -ItemType Directory -Force | Out-Null }

        try {
            # Mirror the folders (meals, planning, etc.) recursively
            # Wildcard '*' ensures we get subfolders like \meals and \planning
            Copy-Item -Path "$SourcePath\*" -Destination $GroupTarget -Recurse -Force -ErrorAction SilentlyContinue
            
            $Stats.Scanned++
            $Stats.Moved++
            Write-Host "    $($Global:Icons.Check) Content mirrored to staged root." -ForegroundColor Green
        } catch {
            Write-Host "    $($Global:Icons.Error) Mirror failed: $($_.Exception.Message)" -ForegroundColor Red
            $Stats.Errors++
        } 
    }
    return $Stats
}

function Global:Write-SentinelSidebars {
    param([string]$SitePath)

    $SidebarPath = Join-Path $SitePath "sidebars.js"
    $DocsPath = Join-Path $SitePath "docs"
    
    $SbContent = "module.exports = {`n  tutorialSidebar: [`n    'index',`n"

    # Scan staged docs for the folders we just moved
    $Groups = Get-ChildItem -Path $DocsPath -Directory | Where-Object { $_.Name -notmatch 'node_modules|src' }

    foreach ($Group in $Groups) {
        $SubFolders = Get-ChildItem -Path $Group.FullName -Directory
        foreach ($Sub in $SubFolders) {
            $Label = "$($Group.Name.Replace('-', ' ').ToUpper()) / $($Sub.Name.ToUpper())"
            $SbContent += "    {`n      type: 'category',`n      label: '$Label',`n"
            $SbContent += "      link: { type: 'generated-index' },`n"
            $SbContent += "      items: [{ type: 'autogenerated', dirName: '$($Group.Name)/$($Sub.Name)' }],`n    },`n"
        }
    }

    $SbContent += "  ],`n};"
    $SbContent | Out-File -FilePath $SidebarPath -Encoding utf8
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

    if ([string]::IsNullOrWhiteSpace($SitePath)) {
        Write-Host "  $($Global:Icons.Error) Cannot start: Path is null." -ForegroundColor Red
        return
    }

    Write-Host "`nPHASE 4: Launching Source Studio Engine (Publicly Accessible)..." -ForegroundColor Cyan

    if (!(Test-Path (Join-Path $SitePath 'node_modules'))) {
        Write-Host "  $($Global:Icons.Info) Initializing Node Modules (First Run)..." -ForegroundColor Gray
        Push-Location $SitePath
        npm install
        Pop-Location
    }

    Stop-Process -Name 'node' -ErrorAction SilentlyContinue

    $StartCommand = "Set-Location '$SitePath'; `$host.UI.RawUI.WindowTitle = 'Sentinel Engine'; npm start -- --host 0.0.0.0"
    
    Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', $StartCommand -WorkingDirectory $SitePath
    
    Write-Host "  $($Global:Icons.Check) Engine spawned in separate window (Listening on 0.0.0.0:3000)." -ForegroundColor Gray
}

function Global:Sync-SentinelGallery {
    param($Source, $Output, $TemplatePath)

    # Load Template with the safer join pattern
    $TemplateContent = (Get-Content -Path $TemplatePath) -join "`r`n"
    if ($null -eq $TemplateContent) { return }

    $MediaFiles = Get-ChildItem -Path $Source -Include "*.jpg","*.png","*.webp" -Recurse

    foreach ($File in $MediaFiles) {
        try {
            $Slug = $File.BaseName
            $FinalContent = $TemplateContent

            # 1. Inject Metadata
            $FinalContent = $FinalContent.Replace("{{Title}}", $Slug)
            $FinalContent = $FinalContent.Replace("{{Slug}}", $Slug)
            $FinalContent = $FinalContent.Replace("{{Date}}", $File.CreationTime.ToString("yyyy-MM-dd"))
            
            # 2. Inject the Image List (Make sure this is below the --- in your .md template!)
            # Example: ![](/img/jems-tones/photo.jpg)
            $ImgMarkup = "![](/img/$($File.Directory.Name)/$($File.Name))"
            $FinalContent = $FinalContent.Replace("{{images_list}}", $ImgMarkup)

            $TargetPath = Join-Path $Output "$Slug.md"
            $FinalContent | Out-File -FilePath $TargetPath -Encoding utf8
            Write-Host "    $($Global:Icons.Check) Generated: $Slug.md" -ForegroundColor Gray
        }
        catch {
            Write-Host "    $($Global:Icons.Error) Fail: $($File.Name)" -ForegroundColor Red
        }
    }
}
function Global:Sync-SentinelShop {
    param($Source, $Output, $TemplatePath)

    # Hardened loading: uses -Raw if available, falls back to -join if not
    try {
        $TemplateContent = Get-Content -Path $TemplatePath -Raw -ErrorAction SilentlyContinue
        if ($null -eq $TemplateContent) { 
            $TemplateContent = (Get-Content -Path $TemplatePath) -join "`r`n" 
        }
    } catch {
        Write-Host "    $($Global:Icons.Error) Critical: Could not read template file." -ForegroundColor Red
        return
    }

    $InventoryItems = Get-ChildItem -Path $Source -Filter "*.yml" -Recurse

    foreach ($Item in $InventoryItems) {
        $Data = Get-Content $Item.FullName -Raw | ConvertFrom-Yaml
        
        # Initialize FinalContent with the template
        $FinalContent = $TemplateContent

        # SAFETY CHECK: Only proceed if template loaded correctly
        if ($null -ne $FinalContent) {
            foreach ($Prop in $Data.PSObject.Properties) {
                # Only attempt replace if the property value is not null
                $Val = if ($null -ne $Prop.Value) { [string]$Prop.Value } else { "" }
                $FinalContent = $FinalContent.Replace("{{$($Prop.Name)}}", $Val)
            }

            # Handle the specific 'Status' logic
            if ($Data.Stock -lt 1) { 
                $FinalContent = $FinalContent.Replace("{{Status}}", "OUT OF STOCK") 
            } else {
                $FinalContent = $FinalContent.Replace("{{Status}}", "IN STOCK")
            }

            $TargetPath = Join-Path $Output "$($Item.BaseName).md"
            $FinalContent | Out-File -FilePath $TargetPath -Encoding utf8
            Write-Host "    $($Global:Icons.Check) Shop Item Generated: $($Item.BaseName)" -ForegroundColor Gray
        }
    }
}