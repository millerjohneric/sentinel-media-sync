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
}function Global:Invoke-SentinelBranding {
    param([string]$SitePath, [string]$TemplateDir)

    Write-Host "`n$($Global:Icons.Check) Injecting Branding & Configs..." -ForegroundColor Cyan

    # 1. Config & Core Overlays (docusaurus.config.js, sidebars.js, nav-registry.json)
    $SrcCfg = Join-Path $TemplateDir 'core-config'
    if (Test-Path $SrcCfg) {
        # Copy root-level configs (.js, .json, .yml) to site root
        Get-ChildItem $SrcCfg -Include *.js, *.json, *.yml | Where-Object { $_.Name -ne 'custom.css' -and $_.Name -ne 'index.js' } | Copy-Item -Destination $SitePath -Force

        # A. Update Global CSS (src/css/custom.css)
        $DstCSS = Join-Path $SitePath 'src/css/custom.css'
        if (!(Test-Path (Split-Path $DstCSS))) { New-Item (Split-Path $DstCSS) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'custom.css')) {
            Copy-Item (Join-Path $SrcCfg 'custom.css') $DstCSS -Force
        }

        # B. Update Homepage Component (src/pages/index.js)
        $DstHome = Join-Path $SitePath 'src/pages/index.js'
        if (!(Test-Path (Split-Path $DstHome))) { New-Item (Split-Path $DstHome) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'index.js')) {
            Copy-Item (Join-Path $SrcCfg 'index.js') $DstHome -Force
        }
    }

    # 2. Component Distribution (GalleryView, ProductView, etc.)
    $SrcComp = Join-Path $TemplateDir 'components'
    $DstComp = Join-Path $SitePath 'src/components'
    if (Test-Path $SrcComp) {
        if (!(Test-Path $DstComp)) { New-Item $DstComp -ItemType Directory -Force | Out-Null }
        Copy-Item (Join-Path $SrcComp '*') $DstComp -Force
    }

    # 3. Branding Assets (Images)
    $SrcImg = Join-Path $TemplateDir 'branding/img'
    $DstImg = Join-Path $SitePath 'static/img'
    if (Test-Path $SrcImg) {
        if (!(Test-Path $DstImg)) { New-Item $DstImg -ItemType Directory -Force | Out-Null }
        robocopy "$SrcImg" "$DstImg" /E /R:0 /W:0 /NJH /NJS /NDL /NFL
    }

    # 4. Content Seed Population (Static Copy for now)
    $SrcSeeds = Join-Path $TemplateDir 'content-seeds'
    if (Test-Path $SrcSeeds) {
        Write-Host "  $($Global:Icons.Info) Populating content seeds..." -ForegroundColor Gray
        
        Get-ChildItem (Join-Path $SrcSeeds 'docs') -Filter "index - *.md" | ForEach-Object {
            $InstanceID = ($_.BaseName -replace 'index - ', '').Trim()
            $TargetDir = Join-Path $SitePath $InstanceID
            
            if (Test-Path $TargetDir) {
                Copy-Item $_.FullName (Join-Path $TargetDir 'index.md') -Force
            }
        }
    }
}

function Global:Initialize-SentinelTemplates {
    param([string]$TemplateDir)

    $Folders = @(
        "branding/img",
        "components",
        "content-seeds/docs",
        "content-seeds/recipes",
        "content-seeds/gallery",
        "content-seeds/shop",
        "core-config"
    )

    # 1. Create Structure
    foreach ($F in $Folders) {
        $Path = Join-Path $TemplateDir $F
        if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force | Out-Null }
    }

    # 2. Define Gold Master Configs & Components
    $Configs = @{
        "core-config/custom.css"           = ":root { --ifm-color-primary: #2e8555; } .navbar { box-shadow: 0 1px 2px 0 rgba(0,0,0,0.1); } .recipe-card { border: 1px solid #ddd; padding: 20px; border-radius: 8px; margin-bottom: 20px; } .media-section { margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px; }"

        "components/RecipeCard.js"         = @'
import React from 'react';
export default function RecipeCard({children, title}) {
    return (
        <div className='recipe-card'>
            <h1>{title}</h1>
            <div className='recipe-content'>
                {children}
            </div>
        </div>
    );
}
'@
        "components/ProductView.js"        = @'
import React from 'react';
export default function ProductView({children, title}) {
    return (
        <div className='shop-view'>
            <h2>{title}</h2>
            <div className='product-details'>
                {children}
            </div>
        </div>
    );
}
'@
        "components/GalleryView.js"        = "import React from 'react';`nexport default function GalleryView({children}) { return (<div className='gallery-grid' style={{display:'flex', flexWrap:'wrap', gap:'10px'}}>{children}</div>); }"
    }


    # 3. Critical Verification Loop (Prompt if missing)
    $CriticalItems = @("branding/img/logo.svg", "core-config/docusaurus.config.js", "core-config/nav-registry.json")
    foreach ($Item in $CriticalItems) {
        $CheckPath = Join-Path $TemplateDir $Item
        if (!(Test-Path $CheckPath)) {
            Write-Host "`n$($Global:Icons.Warning) MISSING: $Item" -ForegroundColor Yellow
            $Response = Read-Host "Generate default from Gold Master? (Y/N)"
            if ($Response -ne 'Y') { Write-Host "Aborted."; exit }

            if ($Item -match 'logo.svg') {
                "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><circle cx='50' cy='50' r='40' fill='green'/></svg>" | Out-File $CheckPath -Encoding UTF8
            }
        }
    }

    # 4. Write missing files
    foreach ($Key in $Configs.Keys) {
        $FilePath = Join-Path $TemplateDir $Key
        if (!(Test-Path $FilePath)) {
            Write-Host "  $($Global:Icons.Check) Seeding: $Key" -ForegroundColor Gray
            $Configs[$Key] | Out-File $FilePath -Encoding UTF8
        }
    }
    Write-Host "  $($Global:Icons.Check) Template Initialization Complete." -ForegroundColor Green
}

function Global:Write-SentinelDocusaurusConfig {
    param([string]$SitePath, [array]$Locations)

    $Plugins = ""
    foreach ($loc in $Locations) {
        # Standardize folder name (Remove potential single quotes from YAML)
        $Folder = if ($loc.WebSubFolder) { $loc.WebSubFolder.Replace("'", "") } else { "" }
        
        # SKIP: Role must be Website, and we skip the default 'docs' folder
        if ($loc.Role -ne 'Website' -or $Folder -eq 'docs' -or [string]::IsNullOrWhiteSpace($Folder)) { continue }

        # Register each folder as a unique Docusaurus documentation instance
        $Plugins += "    ['@docusaurus/plugin-content-docs', { id: '$Folder', path: '$Folder', routeBasePath: '$Folder', sidebarPath: require.resolve('./sidebars.js') }],`n"
    }

    $ConfigTemplate = @'
module.exports = {
  title: 'Source Studio',
  tagline: 'Sentinel Generated',
  url: 'http://millerjohneric.asuscomm.com:3000',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  presets: [
    ['classic', {
      docs: { path: 'docs', sidebarPath: require.resolve('./sidebars.js') },
      theme: { customCss: require.resolve('./src/css/custom.css') }
    }],
  ],
  plugins: [
$Plugins
  ],
};
'@
    $ConfigTemplate | Out-File (Join-Path $SitePath "docusaurus.config.js") -Encoding UTF8 -Force
}

function Global:Write-SentinelSidebars {
    param([string]$SitePath, [array]$Locations)

    $Entries = ""
    foreach ($loc in $Locations) {
        # Standardize path by removing quotes as per Sentinel-Core logic
        $Folder = if ($loc.WebSubFolder) { $loc.WebSubFolder.Replace("'", "") } else { "" }
        
        if ([string]::IsNullOrWhiteSpace($Folder)) { continue }

        # The 'docs' folder is usually the 'defaultSidebar' in Docusaurus classic
        $Id = if ($Folder -eq 'docs') { 'defaultSidebar' } else { $Folder }
        
        # We use 'dirName: .' because each plugin instance is scoped to its own folder
        $Entries += "  '$Id': [{type: 'autogenerated', dirName: '.'}],`n"
    }

    "module.exports = {`n$Entries};" | Out-File (Join-Path $SitePath 'sidebars.js') -Encoding UTF8 -Force
}

function Global:Send-SentinelNotification {
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Stats,
        [Parameter(Mandatory=$true)] [timespan]$Duration,
        [string]$JobName = "Mission Control"
    )

    $Conf = $script:YamlData.Settings.EmailSettings

    # 1. Validation Logic
    if (-not $Conf.Enabled) { return }
    if ([string]::IsNullOrWhiteSpace($script:AppPassword)) {
        Write-Host "  $($Global:Icons.Warning) Email skipped: AppPassword not found." -ForegroundColor Yellow
        return
    }

    # 2. Body Construction (Safe Quoting via Here-String)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $Body = @'
Sentinel Mission Report: $JobName
--------------------------------------------------
Timestamp: $Timestamp
Duration:  $($Duration.ToString('mm\:ss'))

[CHANGE SUMMARY]
Created:   $($Stats.Created)
Updated:   $($Stats.Updated)
Skipped:   $($Stats.Skipped)
Errors:    $($Stats.Errors)
--------------------------------------------------
Site: http://millerjohneric.asuscomm.com:3000
'@

    # 3. Secure Splatting (Fixed Quotes & Logic)
    $MailParams = @{
        'To'          = $Conf.To
        'From'        = $script:GmailUser
        'Subject'     = "Sentinel Report: $JobName ($($Stats.Created) New)"
        'Body'        = $Body
        'SmtpServer'  = "smtp.gmail.com"
        'Port'        = 587
        'UseSsl'      = $true
        # Important: Password must be converted to SecureString for PSCredential
        'Credential'  = New-Object System.Management.Automation.PSCredential(
            $script:GmailUser,
            ($script:AppPassword | ConvertTo-SecureString -AsPlainText -Force)
        )
        'ErrorAction' = 'Stop'
    }

    # 4. Execution
    try {
        Send-MailMessage @MailParams
        Write-Host "  $($Global:Icons.Check) Mission Report Emailed to $($Conf.To)." -ForegroundColor Gray
    }
    catch {
        Write-Host "  $($Global:Icons.Error) Email Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Global:Start-SentinelWebsite {
    param([string]$Path)
    Write-Host "  $($Global:Icons.Check) Handing off to Detached Node Server..." -ForegroundColor Green
    # Detaches the process so the website stays up after the PS window closes
    Start-Process cmd -ArgumentList "/c cd /d `"$Path`" && start /min npm start"
}

function Global:Initialize-SentinelWebRoot {
    param([string]$RootPath, [hashtable]$Settings)

    $CleanPath = $RootPath.Replace("'", "").Trim()
    $PkgPath = Join-Path $CleanPath "package.json"

    # Prune mode forces Purge to false to prevent accidental engine deletion
    $AllowPurge = $Settings.PurgeWebsite
    if ($Settings.PruneWebsite) { $AllowPurge = $false }

    # CRITICAL: If Purge is true, we wipe the folder BEFORE checking for the package
    if ((Test-Path $CleanPath) -and $AllowPurge) {
        Write-Host "  $($Global:Icons.Warning) PurgeWebsite is TRUE: Wiping engine..." -ForegroundColor Yellow
        # Stop node to unlock files
        Stop-Process -Name "node" -ErrorAction SilentlyContinue
        Remove-Item $CleanPath -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    if (!(Test-Path $PkgPath)) {
        Write-Host "  $($Global:Icons.Warning) Engine missing/purged. Scaffolding..." -ForegroundColor Yellow
        # 1. Standard Scaffold Sequence
        $ParentDir = Split-Path $CleanPath -Parent
        $FolderName = Split-Path $CleanPath -Leaf
        if (!(Test-Path $ParentDir)) { New-Item $ParentDir -ItemType Directory -Force | Out-Null }

        Set-Location $ParentDir

        # 2. Run the Zero-Touch Scaffold
        # Using 'echo y |' handles the prompt to proceed without requiring user input
        cmd /c "echo y | npx create-docusaurus@latest $FolderName classic --javascript --skip-install --git-strategy none"

        # 3. Wait for the file system to settle, then scrub the mess
        Start-Sleep -Seconds 5
        Purge-SentinelBoilerplate -SitePath $CleanPath
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

function Global:Purge-SentinelBoilerplate {
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

function Global:Build-WebPageFromTemplate {
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
    param($Tag, $Source, $Path, $Current, $Total, $Time)
    $Percent = [Math]::Round(($Current / $Total) * 100)
    # Formats as: → [GEN] [Culinary] [12/50] (24%) [00:15] filename.mdx
    $Prefix = "  $($Global:Icons.Arrow) [$Tag] [$Source] [$Current/$Total] ($Percent%) [$Time] "

    # Trim path if it exceeds terminal width to keep odometer on one line
    $MaxPathLen = 120 - $Prefix.Length
    $DisplayPath = if ($Path.Length -gt $MaxPathLen) { "..." + $Path.Substring($Path.Length - ($MaxPathLen - 3)) } else { $Path }

    Write-Host "`r$Prefix$DisplayPath" -NoNewline
}

function Global:Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}

function Global:Clean-SentinelContent {
    param([string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return "" }
    $Escaped = $Content -replace '\{', '&#123;' -replace '\}', '&#125;'
    $Escaped = $Escaped -replace '(?m)^:', '\:'
    return $Escaped.Trim()
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

function Global:Write-SentinelCategoryYaml {
    param([string]$FolderPath, [string]$FolderName)

    # Clean the name (e.g., 'dinners-beef' -> 'Dinners Beef')
    $Text = (Get-Culture).TextInfo.ToTitleCase($FolderName.Replace("-", " "))
    
    $Content = @'
label: '$Text'
link:
  type: 'generated-index'
  description: 'Exploring the $Text category.'
'@
    $Content | Out-File (Join-Path $FolderPath '_category_.yml') -Encoding UTF8 -Force
}

function Global:Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot 'index.md'
    $DirName = Split-Path $TargetRoot -Leaf
    $Content = "---`ntitle: '$DirName'`nsidebar_label: 'Overview'`nslug: '/'`n---`n`nimport DocCardList from '@theme/DocCardList';`n`n# $DirName Gallery`n`n<DocCardList />"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}

function Global:Test-SentinelExclusion {
    param([string]$Path)
    $Exclusions = $script:YamlData.'Settings'.'FileTypes'.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
    }
    return $false
}

function Global:Sync-SentinelWebContent {
    param($Locations, $FileTypes)

    # 1. Build the Master Extension List
    $AllowedExtensions = @() # Use a standard array instead of a Generic List

    foreach ($Category in $FileTypes.WebContent) {
        if ($FileTypes.ContainsKey($Category)) {
            $FileTypes.$Category | ForEach-Object { $AllowedExtensions += "*$_" }
        } else {
            $AllowedExtensions += "*$Category"
        }
    }

    foreach ($loc in $Locations) {
        if ($loc.Role -ne 'Website') { continue }

        $Source = $loc.Path.Replace("'", "")
        $TargetDir = $loc.SitePath.Replace("'", "")
        $SubFolder = $loc.WebSubFolder.Replace("'", "")
        $Destination = Join-Path $TargetDir $SubFolder

        if (Test-Path $Source) {
            Write-Host "  $($Global:Icons.Arrow) Syncing $SubFolder (Filtered)..." -ForegroundColor Gray

            $ExcludeDirs = if ($FileTypes.Exclusions) { $FileTypes.Exclusions } else { @() }

            # Use a simple array for ArgumentList
            $RoboArgs = @($Source, $Destination) + $AllowedExtensions + @("/MIR", "/R:0", "/W:0", "/NDL", "/NFL", "/NJH", "/NJS")

            if ($ExcludeDirs.Count -gt 0) {
                $RoboArgs += "/XD"
                $RoboArgs += $ExcludeDirs
            }

            # Run robocopy directly or with correctly formatted arguments
            & robocopy @RoboArgs
        }
    }
}

function Global:Write-SentinelPhase0 {
    param(
        [Parameter(Mandatory=$true)] $Locations,
        [Parameter(Mandatory=$true)] [ValidateSet('Sync', 'Web')] $JobType
    )
    Write-Host '     STATUS      NAME                ROLE                PATH'
    foreach ($loc in $Locations) {
        $IsOnline = Test-Path $loc.Path
        $IsRelevant = if ($JobType -eq 'Web') { $loc.Role -eq 'Website' } else { $loc.MonitorDepth -ge 0 }

        if (-not $IsOnline) { $StatusStr = '[OFFLINE ]'; $StatusColor = 'Red' }
        elseif ($IsRelevant) { $StatusStr = '[ACTIVE  ]'; $StatusColor = 'Green' }
        else { $StatusStr = '[SINK    ]'; $StatusColor = 'DarkGray' }

        $RoleColor = Get-SentinelRoleColor -Role $loc.Role
        Write-Host '     ' -NoNewline
        Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
        Write-Host " [$($loc.Name.PadRight(16))]" -NoNewline
        $RoleDisplay = if ([string]::IsNullOrWhiteSpace($loc.Role)) { "N/A" } else { $loc.Role }
        Write-Host " [$($RoleDisplay.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
        Write-Host $loc.Path -ForegroundColor Gray
    }
}

function Global:Get-SafeYamlTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return "Untitled" }

    # Escape double quotes and wrap the whole title in double quotes
    $CleanTitle = $Title -replace '"', '\"'
    return "`"$CleanTitle`""
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

function Global:Format-SentinelNum {
    param([int]$Number)
    return $Number.ToString('#,0')
}

function Global:Get-SentinelWidth {
    try { return $Host.UI.RawUI.WindowSize.Width - 5 } catch { return 115 }
}

function Global:Get-SafeYaml {
    param($v)
    if ($v) { return $v.ToString().Replace("'", "''") } else { return "" }
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

function Global:Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}

function Global:Format-SentinelNum {
    param([int]$Number)
    return $Number.ToString('#,0')
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

function Global:Get-SentinelWebExtensions {
    param($FileTypeData)
    $FinalList = @()
    foreach ($item in $FileTypeData.WebContent) {
        if ($FileTypeData.ContainsKey($item)) { $FinalList += $FileTypeData.$item }
        else { $FinalList += $item }
    }
    return $FinalList | ForEach-Object { $_.ToLower().TrimStart('.') } | Select-Object -Unique
}

function Global:Get-SentinelWebLocations {
    param($Locations)
    # Filters locations that have a Website role and a defined SitePath
    return $Locations | Where-Object {
        $_.Role -eq 'Website' -and -not [string]::IsNullOrWhiteSpace($_."'SitePath'")
    }
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

function Global:Initialize-SentinelTemplates {
    param([string]$TemplateDir)

    $Folders = @(
        "branding/img",
        "components",
        "content-seeds/docs",
        "content-seeds/recipes",
        "content-seeds/gallery",
        "content-seeds/shop",
        "core-config"
    )

    # 1. Create Structure
    foreach ($F in $Folders) {
        $Path = Join-Path $TemplateDir $F
        if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force | Out-Null }
    }

    # 2. Define Gold Master Configs & Components
    $Configs = @{
        "core-config/custom.css"           = ":root { --ifm-color-primary: #2e8555; } .navbar { box-shadow: 0 1px 2px 0 rgba(0,0,0,0.1); } .recipe-card { border: 1px solid #ddd; padding: 20px; border-radius: 8px; margin-bottom: 20px; } .media-section { margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px; }"

        "components/RecipeCard.js"         = @'
import React from 'react';
export default function RecipeCard({children, title}) {
    return (
        <div className='recipe-card'>
            <h1>{title}</h1>
            <div className='recipe-content'>
                {children}
            </div>
        </div>
    );
}
'@
        "components/ProductView.js"        = @'
import React from 'react';
export default function ProductView({children, title}) {
    return (
        <div className='shop-view'>
            <h2>{title}</h2>
            <div className='product-details'>
                {children}
            </div>
        </div>
    );
}
'@
        "components/GalleryView.js"        = "import React from 'react';`nexport default function GalleryView({children}) { return (<div className='gallery-grid' style={{display:'flex', flexWrap:'wrap', gap:'10px'}}>{children}</div>); }"
    }


    # 3. Critical Verification Loop (Prompt if missing)
    $CriticalItems = @("branding/img/logo.svg", "core-config/docusaurus.config.js", "core-config/nav-registry.json")
    foreach ($Item in $CriticalItems) {
        $CheckPath = Join-Path $TemplateDir $Item
        if (!(Test-Path $CheckPath)) {
            Write-Host "`n$($Global:Icons.Warning) MISSING: $Item" -ForegroundColor Yellow
            $Response = Read-Host "Generate default from Gold Master? (Y/N)"
            if ($Response -ne 'Y') { Write-Host "Aborted."; exit }

            if ($Item -match 'logo.svg') {
                "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><circle cx='50' cy='50' r='40' fill='green'/></svg>" | Out-File $CheckPath -Encoding UTF8
            }
        }
    }

    # 4. Write missing files
    foreach ($Key in $Configs.Keys) {
        $FilePath = Join-Path $TemplateDir $Key
        if (!(Test-Path $FilePath)) {
            Write-Host "  $($Global:Icons.Check) Seeding: $Key" -ForegroundColor Gray
            $Configs[$Key] | Out-File $FilePath -Encoding UTF8
        }
    }
    Write-Host "  $($Global:Icons.Check) Template Initialization Complete." -ForegroundColor Green
}

function Global:Initialize-SentinelWebRoot {
    param([string]$RootPath, [hashtable]$Settings)

    $CleanPath = $RootPath.Replace("'", "").Trim()
    $PkgPath = Join-Path $CleanPath "package.json"

    # Prune mode forces Purge to false to prevent accidental engine deletion
    $AllowPurge = $Settings.PurgeWebsite
    if ($Settings.PruneWebsite) { $AllowPurge = $false }

    # CRITICAL: If Purge is true, we wipe the folder BEFORE checking for the package
    if ((Test-Path $CleanPath) -and $AllowPurge) {
        Write-Host "  $($Global:Icons.Warning) PurgeWebsite is TRUE: Wiping engine..." -ForegroundColor Yellow
        # Stop node to unlock files
        Stop-Process -Name "node" -ErrorAction SilentlyContinue
        Remove-Item $CleanPath -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    if (!(Test-Path $PkgPath)) {
        Write-Host "  $($Global:Icons.Warning) Engine missing/purged. Scaffolding..." -ForegroundColor Yellow
        # 1. Standard Scaffold Sequence
        $ParentDir = Split-Path $CleanPath -Parent
        $FolderName = Split-Path $CleanPath -Leaf
        if (!(Test-Path $ParentDir)) { New-Item $ParentDir -ItemType Directory -Force | Out-Null }

        Set-Location $ParentDir

        # 2. Run the Zero-Touch Scaffold
        # Using 'echo y |' handles the prompt to proceed without requiring user input
        cmd /c "echo y | npx create-docusaurus@latest $FolderName classic --javascript --skip-install --git-strategy none"

        # 3. Wait for the file system to settle, then scrub the mess
        Start-Sleep -Seconds 5
        Purge-SentinelBoilerplate -SitePath $CleanPath
    }
}

function Global:Invoke-SentinelBranding {
    param([string]$SitePath, [string]$TemplateDir)

    Write-Host "`n$($Global:Icons.Check) Injecting Branding Assets..." -ForegroundColor Cyan

    $BrandingSrc = Join-Path $TemplateDir 'branding'
    $StaticDest  = Join-Path $SitePath 'static'
    $ImgDest     = Join-Path $StaticDest 'img'

    if (!(Test-Path $ImgDest)) { 
        New-Item -Path $ImgDest -ItemType Directory -Force | Out-Null 
    }

    if (Test-Path $BrandingSrc) {
        $FaviconPath = Join-Path $BrandingSrc 'favicon.ico'
        if (Test-Path $FaviconPath) {
            Copy-Item $FaviconPath -Destination $StaticDest -Force
            Write-Host '  → Favicon injected.' -ForegroundColor Gray
        }

        $LogoPath = Join-Path $BrandingSrc 'logo.svg'
        if (Test-Path $LogoPath) {
            Copy-Item $LogoPath -Destination $ImgDest -Force
            Write-Host '  → Logo.svg injected.' -ForegroundColor Gray
        }
    }

    # FIX: CSS Path joining for PowerShell 5.1 compatibility
    $SrcCfg = Join-Path $TemplateDir 'core-config'
    if (Test-Path $SrcCfg) {
        $SrcDir = Join-Path $SitePath 'src'
        $DstCSS = Join-Path $SrcDir 'css'
        
        if (!(Test-Path $DstCSS)) { 
            New-Item -Path $DstCSS -ItemType Directory -Force | Out-Null 
        }
        
        Get-ChildItem $SrcCfg -Filter '*.css' | Copy-Item -Destination $DstCSS -Force
        Write-Host '  → CSS Overlays applied.' -ForegroundColor Gray
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

function Global:Send-SentinelNotification {
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Stats,
        [Parameter(Mandatory=$true)] [timespan]$Duration,
        [string]$JobName = "Mission Control"
    )

    $Conf = $script:YamlData.Settings.EmailSettings

    # 1. Validation Logic
    if (-not $Conf.Enabled) { return }
    if ([string]::IsNullOrWhiteSpace($script:AppPassword)) {
        Write-Host "  $($Global:Icons.Warning) Email skipped: AppPassword not found." -ForegroundColor Yellow
        return
    }

    # 2. Body Construction (Safe Quoting via Here-String)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $Body = @'
Sentinel Mission Report: $JobName
--------------------------------------------------
Timestamp: $Timestamp
Duration:  $($Duration.ToString('mm\:ss'))

[CHANGE SUMMARY]
Created:   $($Stats.Created)
Updated:   $($Stats.Updated)
Skipped:   $($Stats.Skipped)
Errors:    $($Stats.Errors)
--------------------------------------------------
Site: http://millerjohneric.asuscomm.com:3000
'@

    # 3. Secure Splatting (Fixed Quotes & Logic)
    $MailParams = @{
        'To'          = $Conf.To
        'From'        = $script:GmailUser
        'Subject'     = 'Sentinel Report: $JobName ($($Stats.Created) New)'
        'Body'        = $Body
        'SmtpServer'  = 'smtp.gmail.com'
        'Port'        = 587
        'UseSsl'      = $true
        # Important: Password must be converted to SecureString for PSCredential
        'Credential'  = New-Object System.Management.Automation.PSCredential(
            $script:GmailUser,
            ($script:AppPassword | ConvertTo-SecureString -AsPlainText -Force)
        )
        'ErrorAction' = 'Stop'
    }

    # 4. Execution
    try {
        Send-MailMessage @MailParams
        Write-Host "  $($Global:Icons.Check) Mission Report Emailed to $($Conf.To)." -ForegroundColor Gray
    }
    catch {
        Write-Host "  $($Global:Icons.Error) Email Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Global:Start-SentinelWebsite {
    param([string]$Path)
    Write-Host "  $($Global:Icons.Check) Handing off to Detached Node Server..." -ForegroundColor Green
    # Detaches the process so the website stays up after the PS window closes
    Start-Process cmd -ArgumentList '/c cd /d `'$Path`' && start /min npm start'
}

function Global:Sync-SentinelWebContent {
    param($Locations, $FileTypes)

    # 1. Build the Master Extension List
    $AllowedExtensions = @() # Use a standard array instead of a Generic List

    foreach ($Category in $FileTypes.WebContent) {
        if ($FileTypes.ContainsKey($Category)) {
            $FileTypes.$Category | ForEach-Object { $AllowedExtensions += "*$_" }
        } else {
            $AllowedExtensions += "*$Category"
        }
    }

    foreach ($loc in $Locations) {
        if ($loc.Role -ne 'Website') { continue }

        $Source = $loc.Path.Replace("'", "")
        $TargetDir = $loc.SitePath.Replace("'", "")
        $SubFolder = $loc.WebSubFolder.Replace("'", "")
        $Destination = Join-Path $TargetDir $SubFolder

        if (Test-Path $Source) {
            Write-Host "  $($Global:Icons.Arrow) Syncing $SubFolder (Filtered)..." -ForegroundColor Gray

            $ExcludeDirs = if ($FileTypes.Exclusions) { $FileTypes.Exclusions } else { @() }

            # Use a simple array for ArgumentList
            $RoboArgs = @($Source, $Destination) + $AllowedExtensions + @("/MIR", "/R:0", "/W:0", "/NDL", "/NFL", "/NJH", "/NJS")

            if ($ExcludeDirs.Count -gt 0) {
                $RoboArgs += "/XD"
                $RoboArgs += $ExcludeDirs
            }

            # Run robocopy directly or with correctly formatted arguments
            & robocopy @RoboArgs
        }
    }
}

function Global:Test-SentinelExclusion {
    param([string]$Path)
    $Exclusions = $script:YamlData.'Settings'.'FileTypes'.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
    }
    return $false
}

function Global:Write-SentinelCategoryYaml {
    param($FolderPath, $FolderName)
    $Path = Join-Path $FolderPath "_category_.yml"
    $Content = "label: '$FolderName'`nlink:`n  type: 'generated-index'`n  description: 'View $FolderName collection.'"
    $Content | Set-Content $Path -Encoding UTF8 -Force
}

function Global:Write-SentinelDocusaurusConfig {
    param([string]$SitePath, [array]$Locations)

    $Plugins = ""
    foreach ($loc in $Locations) {
        # SKIP: Only process Website roles that aren't the primary 'docs' folder
        if ($loc.Role -ne 'Website' -or $loc.WebSubFolder -eq 'docs' -or [string]::IsNullOrWhiteSpace($loc.WebSubFolder)) { continue }

        # Generate a clean JavaScript object string for each plugin
        $Plugins += "    ['@docusaurus/plugin-content-docs', { id: '$($loc.WebSubFolder)', path: '$($loc.WebSubFolder)', routeBasePath: '$($loc.WebSubFolder)', sidebarPath: require.resolve('./sidebars.js') }],`n"
    }

    $ConfigTemplate = @'
module.exports = {
  title: 'Source Studio',
  tagline: 'Sentinel Generated',
  url: 'http://millerjohneric.asuscomm.com:3000',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  favicon: 'favicon.ico', 
  themeConfig: {
    navbar: {
      logo: {
        alt: 'Source Studio Logo',
        src: 'img/logo.svg', 
      },
    },
  },
  presets: [
    ['classic', {
      docs: { path: 'docs', sidebarPath: require.resolve('./sidebars.js') },
      theme: { customCss: require.resolve('./src/css/custom.css') }
    }],
  ],
  plugins: [
$Plugins
  ],
};
'@
    $ConfigTemplate | Out-File (Join-Path $SitePath "docusaurus.config.js") -Encoding UTF8 -Force
}

function Global:Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current, $Total, $Time)
    $Percent = [Math]::Round(($Current / $Total) * 100)
    # Formats as: → [GEN] [Culinary] [12/50] (24%) [00:15] filename.mdx
    $Prefix = "  $($Global:Icons.Arrow) [$Tag] [$Source] [$Current/$Total] ($Percent%) [$Time] "

    # Trim path if it exceeds terminal width to keep odometer on one line
    $MaxPathLen = 120 - $Prefix.Length
    $DisplayPath = if ($Path.Length -gt $MaxPathLen) { "..." + $Path.Substring($Path.Length - ($MaxPathLen - 3)) } else { $Path }

    Write-Host "`r$Prefix$DisplayPath" -NoNewline
}

function Global:Write-SentinelPhase0 {
    param(
        [Parameter(Mandatory=$true)] $Locations,
        [Parameter(Mandatory=$true)] [ValidateSet('Sync', 'Web')] $JobType
    )
    Write-Host '     STATUS      NAME                ROLE                PATH'
    foreach ($loc in $Locations) {
        $IsOnline = Test-Path $loc.Path
        $IsRelevant = if ($JobType -eq 'Web') { $loc.Role -eq 'Website' } else { $loc.MonitorDepth -ge 0 }

        if (-not $IsOnline) { $StatusStr = '[OFFLINE ]'; $StatusColor = 'Red' }
        elseif ($IsRelevant) { $StatusStr = '[ACTIVE  ]'; $StatusColor = 'Green' }
        else { $StatusStr = '[SINK    ]'; $StatusColor = 'DarkGray' }

        $RoleColor = Get-SentinelRoleColor -Role $loc.Role
        Write-Host '     ' -NoNewline
        Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
        Write-Host " [$($loc.Name.PadRight(16))]" -NoNewline
        $RoleDisplay = if ([string]::IsNullOrWhiteSpace($loc.Role)) { "N/A" } else { $loc.Role }
        Write-Host " [$($RoleDisplay.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
        Write-Host $loc.Path -ForegroundColor Gray
    }
}

function Global:Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot 'index.md'
    $DirName = Split-Path $TargetRoot -Leaf
    $Content = "---`ntitle: '$DirName'`nsidebar_label: 'Overview'`nslug: '/'`n---`n`nimport DocCardList from '@theme/DocCardList';`n`n# $DirName Gallery`n`n<DocCardList />"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}

function Global:Write-SentinelSidebars {
    param([string]$SitePath, [array]$Locations)

    $Entries = ""
    foreach ($loc in $Locations) {
        if ([string]::IsNullOrWhiteSpace($loc.WebSubFolder)) { continue }
        $Id = if ($loc.WebSubFolder -eq 'docs') { "defaultSidebar" } else { $loc.WebSubFolder }
        $Entries += "  '$Id': [{type: 'autogenerated', dirName: '.'}],`n"
    }

    "module.exports = {`n$Entries};" | Out-File (Join-Path $SitePath "sidebars.js") -Encoding UTF8 -Force
}
