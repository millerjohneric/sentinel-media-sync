# ==============================================================================
# Sentinel Core Library v5.9 [PRODUCTION READY]
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
    param(
        [string]$Path,
        [string]$Label
    )
    $YamlPath = Join-Path $Path '_category_.yml'
    # Ensuring single quotes for keys as per instructions
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

function Global:Write-SentinelSidebars {
    param([string]$SitePath, [array]$Locations)

    $Websites = $Locations | Where-Object { $null -ne $_.WebSubFolder }
    
    # Create sidebars for the main 'docs' and each additional content plugin
    foreach ($loc in $Websites) {
        $SubFolder = $loc.WebSubFolder.Replace("'", "")
        $SidebarKey = if ($SubFolder -eq 'docs') { "docs" } else { $SubFolder }
        $SidebarFileName = "sidebar-$SidebarKey.js"
        if ($SubFolder -eq 'docs') { $SidebarFileName = "sidebars.js" }
        
        $Label = (Get-Culture).TextInfo.ToTitleCase($SubFolder.Replace("-", " "))

        $Content = @"
module.exports = {
  '$SidebarKey': [
    {
      type: 'category',
      label: '$Label',
      link: { type: 'generated-index', title: '$Label Overview' },
      items: [{type: 'autogenerated', dirName: '.'}],
    },
  ],
};
"@
        $Content | Out-File (Join-Path $SitePath $SidebarFileName) -Encoding UTF8 -Force
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
    # 1. Ensure we actually have YAML data before proceeding
    if ($null -eq $script:YamlData) {
        Write-Host "  $($Global:Icons.Warning) [WAIT] YAML not yet parsed. Skipping secret init." -ForegroundColor Gray
        return
    }

    $Conf = $script:YamlData.Settings.EmailSettings
    $SecretFile = Join-Path $PSScriptRoot ($Conf.CredPath)
    $SecretDir = Split-Path $SecretFile

    # 2. Ensure the .secure directory exists before we try to check for the file
    if (!(Test-Path $SecretDir)) {
        New-Item -Path $SecretDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $SecretFile)) {
        Write-Host "`n$($Global:Icons.Warning) [SECURITY] No credentials found for $($Conf.To)" -ForegroundColor Yellow
        $RawPass = Read-Host "Paste your 16-character GMail App Password"
        $CleanPass = $RawPass.Trim().Replace(" ", "").Replace("`t", "")

        if ($CleanPass.Length -ne 16) {
            Write-Host "$($Global:Icons.Error) [CRITICAL] Gmail App Passwords must be 16 chars." -ForegroundColor Red
            return
        }

        $SecPass = ConvertTo-SecureString $CleanPass -AsPlainText -Force
        New-Object System.Management.Automation.PSCredential($Conf.To, $SecPass) | Export-CliXml -Path $SecretFile
        Write-Host "$($Global:Icons.Check) [SUCCESS] Password encrypted." -ForegroundColor Green
    }

    # 3. Final Load Check
    if (Test-Path $SecretFile) {
        try {
            $TempCred = Import-CliXml -Path $SecretFile
            $script:GmailUser = $TempCred.UserName
            $script:AppPassword = $TempCred.GetNetworkCredential().Password
        } catch {
            Write-Host "$($Global:Icons.Error) Failed to decrypt $SecretFile. You may need to delete it and re-enter." -ForegroundColor Red
        }
    }
}

function Global:Initialize-SentinelWebRoot {
    param(
        [string]$RootPath, 
        $Settings,
        $Locations
    )

    $CleanPath = $RootPath.Replace("'", "").Trim()
    $Purge = $Settings.PurgeWebsite
    $Prune = $Settings.PruneWebsite
    if ($Prune) { $Purge = $false }

    if (Test-Path $CleanPath) {
        if ($Purge) {
            Write-Host "  $($Global:Icons.Warning) Purge: Wiping EVERYTHING..." -ForegroundColor Yellow
            Stop-Process -Name 'node' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Remove-Item $CleanPath -Recurse -Force -ErrorAction SilentlyContinue
        } 
        elseif ($Prune) {
            Write-Host "  $($Global:Icons.Arrow) Pruning content siblings..." -ForegroundColor Cyan
            $Protected = @('node_modules', '.docusaurus', 'src', 'static', '.git', 'package.json', 'package-lock.json', 'babel.config.js', 'docusaurus.config.js', 'sidebars.js')
            
            Get-ChildItem $CleanPath | Where-Object { $Protected -notcontains $_.Name } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Scaffold if missing
    if (!(Test-Path (Join-Path $CleanPath 'package.json'))) {
        Write-Host "  $($Global:Icons.Warning) Engine missing. Rebuilding Scaffold..." -ForegroundColor Yellow
        $ParentDir = Split-Path $CleanPath -Parent
        $FolderName = Split-Path $CleanPath -Leaf
        
        Push-Location $ParentDir
        try {
            # Scaffold to a temp name to avoid 'Directory exists' error, then move contents
            $TempName = "staged_$($FolderName)"
            cmd /c "echo y | npx create-docusaurus@latest $TempName classic --javascript --skip-install"
            
            if (!(Test-Path $CleanPath)) { New-Item $CleanPath -ItemType Directory -Force | Out-Null }
            Move-Item "$TempName\*" $CleanPath -Force
            Remove-Item $TempName -Recurse -Force
        } finally {
            Pop-Location
        }
    }

    # Ensure Sibling Folders exist under SitePath
    foreach ($Loc in $Locations) {
        if ($Loc.Role -ne 'Website') { continue }
        $SubPath = Join-Path $CleanPath $Loc.WebSubFolder
        if (!(Test-Path $SubPath)) { 
            New-Item $SubPath -ItemType Directory -Force | Out-Null 
        }
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
    param([string]$Path)
    $Exclusions = $script:YamlData.'Settings'.'FileTypes'.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
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

function Global:Purge-SentinelBoilerplate {
    param([string]$SitePath)
    # Maps the call to your existing logic
    Global:Remove-SentinelBoilerplate -SitePath $SitePath
}

function Global:Invoke-SentinelRecipeGeneration {
    param([string]$SourceDataDir, [string]$TargetDir, [string]$TemplatePath)
    # Maps the call to your existing content logic
    Global:Invoke-SentinelRecipeContent -SourceDataDir $SourceDataDir -TargetDir $TargetDir -TemplatePath $TemplatePath
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
    param(
        [string]$SitePath,
        $YamlData
    )

    $ConfigPath = Join-Path $SitePath 'docusaurus.config.js'
    $SafeUrl = if ($YamlData.Settings.SiteUrl) { $YamlData.Settings.SiteUrl } else { 'http://localhost:3000' }
    
    # Get all Website Locations
    $WebLocs = $YamlData.Locations | Where-Object { $_.Role -eq 'Website' }
    
    # Identify Sibling Plugins (Anything NOT web-root)
    $Plugins = $WebLocs | Where-Object { $_.RootType -ne 'web-root' }

    $PluginBlocks = ""
    foreach ($P in $Plugins) {
        $Folder = $P.WebSubFolder
        $ID = $Folder.Replace("-", "").ToLower()
        # Per instruction: all other locations belong as siblings to the docs folder
        $Sidebar = "./sidebar-$Folder.js"
        
        $PluginBlocks += @"
    [
      '@docusaurus/plugin-content-docs',
      {
        'id': '$ID',
        'path': '$Folder',
        'routeBasePath': '$Folder',
        'sidebarPath': require.resolve('$Sidebar'),
      },
    ],
"@
    }

    $NavLinks = ""
    foreach ($loc in $WebLocs) {
        $Label = (Get-Culture).TextInfo.ToTitleCase($loc.WebSubFolder.Replace("-", " "))
        $Path = if ($loc.RootType -eq 'web-root') { 'docs/intro' } else { "$($loc.WebSubFolder)/" }
        $NavLinks += "        {to: '$Path', label: '$Label', position: 'left'},`n"
    }

    $ConfigBody = @"
const config = {
  'title': 'Sentinel Source Studio',
  'url': '$SafeUrl',
  'baseUrl': '/',
  'onBrokenLinks': 'warn',
  'presets': [
    [
      'classic',
      {
        'docs': {
          'path': 'docs',
          'sidebarPath': require.resolve('./sidebars.js'),
        },
        'theme': { 'customCss': require.resolve('./src/css/custom.css') },
      },
    ],
  ],
  'plugins': [
$PluginBlocks
  ],
  'themeConfig': {
    'navbar': {
      'title': 'Sentinel',
      'items': [
$NavLinks
      ],
    },
  },
};

module.exports = config;
"@

    $ConfigBody | Out-File -FilePath $ConfigPath -Encoding utf8 -Force
    Write-Host "  $($Global:Icons.Check) Dynamic config updated: $($Plugins.Count) plugins registered." -ForegroundColor Gray
}
function Global:Start-SentinelProduction {
    param($SitePath)
    Write-Host "`nPHASE 4: Finalizing & Handing off to Node..." -ForegroundColor Cyan
    Stop-Process -Name "node" -ErrorAction SilentlyContinue
    Set-Location $SitePath
    npm start
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
    
    if ($null -eq $loc.Template) { return }
    $TemplateRaw = $loc.Template.ToString().Replace("'", "")
    
    # Simple regex to extract [Category] and TemplateName
    if ($TemplateRaw -match '^\[([^\]]+)\](.+)$') {
        $Category = $Matches[1].ToLower().Trim()
        $TName = $Matches[2].TrimStart('\').Replace(".md", "")
        # Single quotes for key path as requested
        $RelPath = 'content-seeds\' + $Category + '\' + $TName + '.md'
    } else {
        $RelPath = $TemplateRaw.TrimStart('\')
    }

    $FullTemplatePath = Join-Path $Settings.TemplateDir $RelPath
    # Clean up subfolder pathing
    $CleanSub = $loc.WebSubFolder.ToString().Replace("'", "").Trim()
    $TargetDir = Join-Path $TargetWebsitePath $CleanSub

    if (Test-Path $FullTemplatePath -PathType Leaf) {
        Invoke-SentinelRecipeContent -SourceDataDir $loc.Path -TargetDir $TargetDir -TemplatePath $FullTemplatePath
    }
}

function Global:Sync-SentinelMedia {
    param($Locations, $Settings)
    Write-Host "PHASE 1: Organizing Media Assets..." -ForegroundColor Cyan
    
    $PickupLocs = $Locations | Where-Object { $_.Role -eq 'Pickup' }
    $Stats = @{ Scanned = 0; Moved = 0; Errors = 0 }

    foreach ($loc in $PickupLocs) {
        if (!(Test-Path $loc.Path)) { continue }
        
        $Files = Get-ChildItem -Path $loc.Path -File -Recurse -ErrorAction SilentlyContinue
        $count = 0

        foreach ($file in $Files) {
            $count++; $Stats.Scanned++
            $CleanName = "$($file.BaseName)$($file.Extension.ToLower())"
            $DestDir = Join-Path "C:\Source\GEEK\Photo_Archive\Sorting_Limbo" $loc.Name
            
            if (!(Test-Path $DestDir)) { New-Item $DestDir -ItemType Directory -Force | Out-Null }
            $FullDest = Join-Path $DestDir $CleanName

            try {
                Write-SentinelOdometer -Tag 'MOVE' -Source $loc.Name -Path $CleanName -Current $count -Total $Files.Count
                Move-Item -Path $file.FullName -Destination $FullDest -Force -ErrorAction Stop
                $Stats.Moved++
            } catch { $Stats.Errors++ }
        }
        
        # TARGETED PURGE: Wrapped in Try/Catch to handle "Access Denied" (WhatsApp/Android)
        Get-ChildItem $loc.Path -Recurse -Directory -ErrorAction SilentlyContinue | 
            Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                try {
                    if ((Get-ChildItem $_.FullName -Recurse -ErrorAction Stop).Count -eq 0) {
                        Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                    }
                } catch {
                    # Skip folders we don't have permission to touch
                }
            }
        Write-Host ""
    }
    return $Stats
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