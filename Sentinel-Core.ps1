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

function Global:Send-SentinelNotification {
    param($Stats, $Duration, $JobName)

    $Email = $YamlData.Settings.EmailSettings
    # Resolves C:\Source\GEEK\Sentinel\sentinel-media-sync\.secure\gmail.cred
    $CredPath = Join-Path $PSScriptRoot $Email.CredPath

    if (!(Test-Path $CredPath)) {
        Write-Host "  $($Global:Icons.Error) Email failed: Credentials missing at $CredPath" -ForegroundColor Red
        return
    }

    try {
        $Cred = Import-CliXml -Path $CredPath
        $Body = @"
Sentinel Mission Report
-----------------------
Job: $JobName
Duration: $($Duration.Minutes)m $($Duration.Seconds)s

Results:
- Scanned: $($Stats.Scanned)
- Created: $($Stats.Created)
- Errors:  $($Stats.Errors)
"@

        Send-MailMessage `
            -To $Email.To `
            -From $Email.To `
            -Subject "[$JobName] Build Success" `
            -Body $Body `
            -SmtpServer 'smtp.gmail.com' `
            -Port 587 `
            -UseSsl `
            -Credential $Cred
            
        Write-Host "  $($Global:Icons.Check) Mission Report Sent to $($Email.To)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  $($Global:Icons.Error) SMTP Error: $($_.Exception.Message)" -ForegroundColor Red
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

function Global:Write-SentinelSidebars {
    param([string]$SitePath, [array]$Locations)

    foreach ($loc in $Locations) {
        if ($null -eq $loc.WebSubFolder) { continue }
        
        $ID = $loc.WebSubFolder.Replace("-", "")
        $SidebarFileName = "sidebars" + ($ID.Substring(0,1).ToUpper() + $ID.Substring(1)) + ".js"
        $SidebarPath = Join-Path $SitePath $SidebarFileName
        $Label = (Get-Culture).TextInfo.ToTitleCase($loc.WebSubFolder.Replace("-", " "))

        $Content = @"
module.exports = {
  $($ID)Sidebar: [
    {
      type: 'category',
      label: '$Label',
      link: { 
        type: 'generated-index', 
        title: '$Label Gallery',
        slug: '/index' 
      },
      items: [{type: 'autogenerated', dirName: '.'}],
    },
  ],
};
"@
        $Content | Out-File $SidebarPath -Encoding UTF8 -Force
        Write-Host "  $($Global:Icons.Check) Created Sidebar: $SidebarFileName" -ForegroundColor Gray
    }
}


function Global:Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot 'index.md'
    $DirName = Split-Path $TargetRoot -Leaf
    $Content = "---`ntitle: '$DirName'`nsidebar_label: 'Overview'`nslug: '/'`n---`n`nimport DocCardList from '@theme/DocCardList';`n`n# $DirName Gallery`n`n<DocCardList />"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
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
        [Parameter(Mandatory=$true)] $YamlData,
        [Parameter(Mandatory=$false)] $TargetWebsitePath
    )

    Write-Host '     STATUS      NAME                ROLE                PATH'
    
    # Extract locations regardless of casing in YAML keys
    $Locs = if ($YamlData.Locations) { $YamlData.Locations } else { $YamlData.locations }

    foreach ($loc in $Locs) {
        $IsOnline = Test-Path $loc.Path
        
        # Determine Status Priority
        if (-not $IsOnline) { 
            $StatusStr = '[OFFLINE ]'; $StatusColor = 'Red' 
        }
        elseif ($loc.Role -eq 'Website') { 
            # This ensures your 4 websites stand out
            $StatusStr = '[TARGET  ]'; $StatusColor = 'Cyan' 
        }
        elseif ($loc.MonitorDepth -ge 0) { 
            # Preserves functionality for Archives/Pickups
            $StatusStr = '[ACTIVE  ]'; $StatusColor = 'Green' 
        }
        else { 
            $StatusStr = '[SINK    ]'; $StatusColor = 'DarkGray' 
        }

        $RoleColor = Get-SentinelRoleColor -Role $loc.Role
        
        Write-Host '     ' -NoNewline
        Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
        Write-Host " [$($loc.Name.PadRight(16))]" -NoNewline
        
        $RoleDisplay = if ([string]::IsNullOrWhiteSpace($loc.Role)) { "N/A" } else { $loc.Role }
        Write-Host " [$($RoleDisplay.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
        Write-Host $loc.Path -ForegroundColor Gray
    }

    if ($TargetWebsitePath) {
        Write-Host "`n  $($Global:Icons.Arrow) Target Engine: $TargetWebsitePath" -ForegroundColor Cyan
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
    param([string]$RootPath, [hashtable]$Settings)

    $CleanPath = $RootPath.Replace("'", "").Trim()
    $AllowPurge = $Settings.PurgeWebsite

    if ((Test-Path $CleanPath) -and $AllowPurge) {
        Write-Host "  $($Global:Icons.Warning) PurgeWebsite is TRUE: Wiping engine..." -ForegroundColor Yellow
        
        # 1. Kill Node to unlock files
        Stop-Process -Name 'node' -ErrorAction SilentlyContinue
        
        # 2. STEP OUT of the directory to unlock the folder itself
        if ($PWD.Path -like "$CleanPath*") {
            Set-Location (Split-Path $CleanPath -Parent)
        }
        
        Start-Sleep -Seconds 2
        Remove-Item $CleanPath -Recurse -Force -ErrorAction SilentlyContinue
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

function Global:Start-SentinelWebsite {
    param([string]$Path)
    
    # 1. Clean the path to ensure no trailing/leading quotes exist before we wrap it
    $CleanPath = $Path.Trim().Replace("'", "")
    
    Write-Host "  $($Global:Icons.Check) Launching Node Server (0.0.0.0:3000)..." -ForegroundColor Green
    
    # 2. Kill ghost processes to prevent port refusal
    Stop-Process -Name 'node' -Force -ErrorAction SilentlyContinue

    # 3. Use escaped double quotes for the CMD path to prevent syntax errors
    # /k keeps the window open so you can see if NPM fails
    Start-Process cmd -ArgumentList "/k cd /d `"$CleanPath`" && npm start -- --host 0.0.0.0"
}


function Global:Test-SentinelExclusion {
    param([string]$Path)
    $Exclusions = $script:YamlData.'Settings'.'FileTypes'.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
    }
    return $false
}

function Global:Write-SentinelDocusaurusConfig {
    param([string]$SitePath, [array]$Locations)

    $PluginBlocks = ""
    $NavbarItems = ""

    foreach ($loc in $Locations) {
        if ($null -eq $loc.WebSubFolder -or $loc.WebSubFolder -eq 'docs') { continue }
        
        $ID = $loc.WebSubFolder.Replace('-', '')
        $FolderName = $loc.WebSubFolder
        $SidebarName = 'sidebars' + ($ID.Substring(0,1).ToUpper() + $ID.Substring(1)) + '.js'
        $Label = (Get-Culture).TextInfo.ToTitleCase($FolderName.Replace('-', ' '))

        $PluginBlocks += @"
    [
      '@docusaurus/plugin-content-docs',
      {
        'id': '$ID',
        'path': '$FolderName',
        'routeBasePath': '$FolderName',
        'sidebarPath': require.resolve('./$SidebarName'),
      },
    ],
"@
        $NavbarItems += "        {to: '/$FolderName/', label: '$Label', position: 'left'},`n"
    }

    $ConfigContent = @"
const config = {
  'title': 'Sentinel Studio',
  'tagline': 'Automated Media Sync',
  'url': 'http://localhost:3000',
  'baseUrl': '/',
  'onBrokenLinks': 'ignore',
  'markdown': {
    'mermaid': true,
  },
  'favicon': 'img/favicon.ico',
  'presets': [
    [
      'classic',
      {
        'docs': { 
          'sidebarPath': require.resolve('./sidebars.js'),
          'path': 'docs',
          'routeBasePath': 'docs',
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
        {type: 'doc', docId: 'index', position: 'left', label: 'Docs'},
$NavbarItems
      ],
    },
  },
};

module.exports = config;
"@

    $ConfigContent | Out-File (Join-Path $SitePath 'docusaurus.config.js') -Encoding UTF8 -Force
    Write-Host "  $($Global:Icons.Check) Docusaurus Config Generated (Navbar fixed to index)" -ForegroundColor Gray
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