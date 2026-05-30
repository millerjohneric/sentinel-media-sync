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

    Write-Host "`n  $($Global:Icons.Arrow) Processing Pipeline: Culinary Cuisine" -ForegroundColor Cyan

    if (!(Test-Path $Output)) { New-Item -Path $Output -ItemType Directory -Force | Out-Null }

    # Walk all jpg files recursively — each jpg = one recipe page
    $RecipeImages = Get-ChildItem -Path $Source -Include "*.jpg","*.jpeg","*.png" -Recurse |
        Where-Object { $_.Name -notmatch '^\.' }

    if ($RecipeImages.Count -eq 0) {
        Write-Host "    $($Global:Icons.Warning) No recipe images found in: $Source" -ForegroundColor Yellow
        return
    }

    $PageCount = 0
    # Group files by their base name prefix (before -.- separator)
    $GroupSep = '-.-'
    $Groups = $RecipeImages | Group-Object {
        $base = $_.BaseName
        if ($base -match [regex]::Escape($GroupSep)) {
            $base.Substring(0, $base.LastIndexOf($GroupSep))
        } else { $base }
    }

    foreach ($Group in $Groups) {
        $GroupName = $Group.Name
        $Images    = $Group.Group

        # Use the first image's directory for output path
        $FirstImg  = $Images[0]
        $RawName   = $GroupName -replace '[-_]', ' '
        $Title     = (Get-Culture).TextInfo.ToTitleCase($RawName.ToLower())
        $CleanTitle = $Title -replace "['""]", ""

        $RelDir    = $FirstImg.DirectoryName.Replace($Source, "").TrimStart('\')
        $TargetDir = if ($RelDir) { Join-Path $Output $RelDir } else { $Output }
        if (!(Test-Path $TargetDir)) { New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null }

        # Copy all images for this group
        $ImgMarkup = ""
        foreach ($Img in $Images) {
            $ImgDest = Join-Path $TargetDir $Img.Name
            if (!(Test-Path $ImgDest)) { Copy-Item $Img.FullName $ImgDest -Force }
            $ImgMarkup += "`n<img src={require('./$($Img.Name)').default} alt='$CleanTitle' style={{maxWidth:'100%', borderRadius:'8px', marginBottom:'1rem'}} />`n"
        }

        # Extract recipe data from sidecar files
        $ServerYmlPath = Join-Path $FirstImg.DirectoryName "$GroupName.yml"
        if (!(Test-Path $ServerYmlPath)) {
            $TemplateYml = @"
Recipe: "$CleanTitle"
PrepTime: ""
CookTime: ""
Servings: ""
Ingredients:
  - 
Instructions:
  - 
Tags:
  - 
"@
            [System.IO.File]::WriteAllText($ServerYmlPath, $TemplateYml, [System.Text.UTF8Encoding]::new($false))
        }

        $RecipeData = Get-SentinelRecipeData -ImageDir $FirstImg.DirectoryName -BaseName $GroupName

        # Build content with recipe data
        $RecipeContent = Format-RecipeData -RecipeData $RecipeData

        $UrlPath = $ServerYmlPath.Replace('\', '/')
        $MappedPath = $UrlPath.Replace($Source.Replace('//LS720DB34C/share/', 'L:/'), '').TrimStart('/')
        $AdminMarkup = @"

---

:::info Admin
**Edit Recipe Sidecar:** [Open in VS Code](vscode://file/$UrlPath) | Path: <code>$UrlPath</code>
:::
"@

        $Content = @"
---
title: '$CleanTitle'
---

$RecipeContent

$ImgMarkup
$AdminMarkup
"@

        $TargetPath = Join-Path $TargetDir "$GroupName.mdx"
        [System.IO.File]::WriteAllText($TargetPath, $Content, [System.Text.UTF8Encoding]::new($false))
        $PageCount++
    }

    Write-Host "    $($Global:Icons.Check) Recipe Module: $PageCount pages generated." -ForegroundColor Green

    # --- Generate index.mdx for every subfolder (thumbnail grid of contents) ---
    $AllOutputDirs = Get-ChildItem -Path $Output -Directory -Recurse
    # Also include the root output dir
    $DirsToIndex = @($AllOutputDirs) + @(Get-Item $Output)

    foreach ($Dir in $DirsToIndex) {
        $DirName  = $Dir.Name
        $Label    = (Get-Culture).TextInfo.ToTitleCase($DirName.Replace('-', ' '))

        # Get subfolders — show as category cards
        $SubDirs  = Get-ChildItem $Dir.FullName -Directory
        # Get images directly in this folder for recipe thumbnails — exclude _thumb_ files
        $DirImgs  = Get-ChildItem $Dir.FullName -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' -and $_.Name -notmatch '^_thumb_' } | Select-Object -First 12
        # Also get markdown/mdx files that have no image (text-only recipes)
        $DirDocs  = Get-ChildItem $Dir.FullName -File | Where-Object { $_.Extension -match '\.(md|mdx)$' -and $_.Name -notmatch '^index\.' } | Select-Object -First 12

        $Cards = ""

        # Build the absolute doc path for this folder (e.g. /docs/culinary-cuisine/meals)
        $RelFromOutput = $Dir.FullName.Replace($Output, '').TrimStart('\').Replace('\','/')
        $DocBasePath = if ($RelFromOutput) { "/docs/$($Output.Split('\')[-1])/$RelFromOutput" } else { "/docs/$($Output.Split('\')[-1])" }

        # Subfolder cards with thumbnails
        foreach ($Sub in $SubDirs) {
            $SubLabel = (Get-Culture).TextInfo.ToTitleCase($Sub.Name.Replace('-', ' '))
            $SubSlug  = $Sub.Name
            $SubFullPath = "$DocBasePath/$SubSlug"
            # Count unique recipe groups (not individual files)
            $AllFiles = Get-ChildItem $Sub.FullName -File -Recurse | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|md|mdx)$' -and $_.Name -notmatch '^_thumb_' -and $_.Name -notmatch '^index\.' }
            $RecipeCount = ($AllFiles | Group-Object {
                $base = $_.BaseName
                if ($base -match [regex]::Escape($GroupSep)) {
                    $base.Substring(0, $base.LastIndexOf($GroupSep))
                } else { $base }
            }).Count

            # Pick a RANDOM image from subfolder (recursive) — changes each sync
            $AllThumbs = Get-ChildItem $Sub.FullName -File -Recurse | Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' }
            $Thumb = if ($AllThumbs.Count -gt 0) { $AllThumbs | Get-Random } else { $null }
            $ThumbMarkup = ""
            if ($Thumb) {
                $ThumbName = "_thumb_$SubSlug$($Thumb.Extension)"
                $ThumbDest = Join-Path $Dir.FullName $ThumbName
                Copy-Item $Thumb.FullName $ThumbDest -Force
                $ThumbMarkup = "<img src={require('./$ThumbName').default} alt='$SubLabel' style={{width:'100%', height:'130px', objectFit:'cover'}} />"
            }

            $Cards += @"
<a href='$SubFullPath' style={{textDecoration:'none', color:'inherit'}}>
  <div style={{border:'1px solid var(--card-border)', borderRadius:'10px', overflow:'hidden', background:'var(--card-bg)', transition:'transform 0.2s, box-shadow 0.2s'}} onMouseOver={e=>{e.currentTarget.style.transform='translateY(-3px)';e.currentTarget.style.boxShadow='0 6px 20px rgba(0,0,0,0.1)'}} onMouseOut={e=>{e.currentTarget.style.transform='';e.currentTarget.style.boxShadow=''}}>
    $ThumbMarkup
    <div style={{padding:'0.6rem 0.8rem'}}>
      <div style={{fontWeight:600, fontSize:'0.95rem'}}>$SubLabel</div>
      <div style={{fontSize:'0.78rem', color:'var(--ifm-color-secondary)', marginTop:'2px'}}>$RecipeCount pages</div>
    </div>
  </div>
</a>
"@
        }

        # Recipe cards for files directly in this folder (no subfolders)
        # Group files by their base name prefix (before -.- separator)
        $GroupSep = '-.-'
        $Groups = $DirImgs | Group-Object {
            $base = $_.BaseName
            if ($base -match [regex]::Escape($GroupSep)) {
                $base.Substring(0, $base.LastIndexOf($GroupSep))
            } else { $base }
        }

        foreach ($Group in $Groups) {
            $GroupName = $Group.Name
            $Images    = $Group.Group
            $FirstImg  = $Images[0]

            $RawName = $GroupName -replace '[-_]', ' '
            $RecipeTitle = (Get-Culture).TextInfo.ToTitleCase($RawName.ToLower()) -replace "['""]", ""
            $RecipeFullPath = "$DocBasePath/$GroupName"

            # Pick one thumbnail from the group
            $Thumb = $FirstImg
            $ThumbName = "_thumb_$GroupName$($Thumb.Extension)"
            $ThumbDest = Join-Path $Dir.FullName $ThumbName
            Copy-Item $Thumb.FullName $ThumbDest -Force

            $Cards += @"
<a href='$RecipeFullPath' style={{textDecoration:'none', color:'inherit'}}>
  <div style={{border:'1px solid var(--card-border)', borderRadius:'10px', overflow:'hidden', background:'var(--card-bg)', transition:'transform 0.2s, box-shadow 0.2s'}} onMouseOver={e=>{e.currentTarget.style.transform='translateY(-3px)';e.currentTarget.style.boxShadow='0 6px 20px rgba(0,0,0,0.1)'}} onMouseOut={e=>{e.currentTarget.style.transform='';e.currentTarget.style.boxShadow=''}}>
    <img src={require('./$ThumbName').default} alt='$RecipeTitle' style={{width:'100%', height:'130px', objectFit:'cover'}} />
    <div style={{padding:'0.6rem 0.8rem', fontWeight:500, fontSize:'0.9rem'}}>$RecipeTitle</div>
    <div style={{fontSize:'0.78rem', color:'var(--ifm-color-secondary)', padding:'0 0.6rem 0.6rem'}}>$($Images.Count) photos</div>
  </div>
</a>
"@
        }

        if ($Cards -eq "" -and $DirDocs.Count -eq 0) { continue }

        # Add text-only doc cards for folders with no images
        # Group files by their base name prefix (before -.- separator)
        $Groups = $DirDocs | Group-Object {
            $base = $_.BaseName
            if ($base -match [regex]::Escape($GroupSep)) {
                $base.Substring(0, $base.LastIndexOf($GroupSep))
            } else { $base }
        }

        foreach ($Group in $Groups) {
            $GroupName = $Group.Name
            $Docs = $Group.Group
            $FirstDoc = $Docs[0]

            $RawName = $GroupName -replace '[-_]', ' '
            $DocTitle = (Get-Culture).TextInfo.ToTitleCase($RawName.ToLower()) -replace "['""]", ""
            $DocFullPath = "$DocBasePath/$GroupName"
            $Cards += @"
<a href='$DocFullPath' style={{textDecoration:'none', color:'inherit'}}>
  <div style={{border:'1px solid var(--card-border)', borderRadius:'10px', padding:'1rem 1.25rem', background:'var(--card-bg)', transition:'transform 0.2s, box-shadow 0.2s'}} onMouseOver={e=>{e.currentTarget.style.transform='translateY(-3px)';e.currentTarget.style.boxShadow='0 6px 20px rgba(0,0,0,0.1)'}} onMouseOut={e=>{e.currentTarget.style.transform='';e.currentTarget.style.boxShadow=''}}>
    <div style={{fontWeight:500, fontSize:'0.95rem'}}>$DocTitle</div>
  </div>
</a>
"@
        }

        $IndexContent = @"
---
title: '$Label'
sidebar_label: '$Label'
sidebar_position: 0
---

# $Label

<div style={{display:'grid', gridTemplateColumns:'repeat(auto-fill, minmax(180px, 1fr))', gap:'1rem', padding:'1rem 0'}}>
$Cards
</div>
"@
        [System.IO.File]::WriteAllText((Join-Path $Dir.FullName "index.mdx"), $IndexContent, [System.Text.UTF8Encoding]::new($false))
    }

    # Remove any old index.md files that conflict
    Get-ChildItem $Output -Filter "index.md" -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "    $($Global:Icons.Check) Category indexes generated." -ForegroundColor Green
}
function Global:Sync-SentinelGallery {
    param($Source, $Output, $TemplateDir)

    Write-Host "`n  $($Global:Icons.Arrow) Processing Pipeline: Gallery" -ForegroundColor Cyan

    # Noise words to filter out when building titles from XMP subjects
    $NoiseWords = @('colorful','colorless','bokeh','unsaturated','black and white',
                    'complementary colors','drinking accessoire','nature','animal',
                    'person','wood','plant','tree','waters','vehicle','sky',
                    'mammal','herbivore','arthropod','insect','rodent')

    if (!(Test-Path $Output)) { New-Item -Path $Output -ItemType Directory -Force | Out-Null }

    $ImageFiles = Get-ChildItem -Path $Source -Include "*.jpg","*.jpeg","*.png","*.webp" -Recurse

    if ($ImageFiles.Count -eq 0) {
        Write-Host "    $($Global:Icons.Warning) No images found in: $Source" -ForegroundColor Yellow
        return
    }

    # Group by date prefix (YYYYMMDD)
    $Sessions = $ImageFiles | Group-Object { 
        if ($_.BaseName -match '^(\d{8})') { $Matches[1] } else { 'misc' }
    }

    $PageCount = 0
    $IndexCards = ""  # for the overview index page

    foreach ($Session in $Sessions) {
        $DateKey = $Session.Name
        $Images  = $Session.Group

        # --- READ XMP DATA FOR THIS SESSION ---
        $SubjectFreq = @{}
        $AllGalleryData = @()
        foreach ($Img in $Images) {
            $XmpPath = Join-Path $Img.DirectoryName "$($Img.BaseName).xmp"
            if (Test-Path $XmpPath) {
                $XmpContent = Get-Content $XmpPath -Raw -ErrorAction SilentlyContinue
                if ($XmpContent -match '(?s)<dc:subject>.*?<rdf:Bag>(.*?)</rdf:Bag>') {
                    $Matches[1] | Select-String -Pattern '<rdf:li>(.*?)</rdf:li>' -AllMatches |
                        ForEach-Object { $_.Matches } |
                        ForEach-Object {
                            $Word = $_.Groups[1].Value.Trim()
                            if ($NoiseWords -notcontains $Word.ToLower()) {
                                $SubjectFreq[$Word] = ($SubjectFreq[$Word] -as [int]) + 1
                            }
                        }
                }
                # Collect gallery data from first image's XMP
                if ($Img -eq $Images[0]) {
                    $AllGalleryData = Get-SentinelGalleryData -ImageDir $Img.DirectoryName -BaseName $Img.BaseName
                }
            }
        }

        # Pick top 2 subjects by frequency, fall back to formatted date
        $TopSubjects = $SubjectFreq.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 2 | ForEach-Object { $_.Key }
        $Title = if ($TopSubjects.Count -gt 0) {
            ($TopSubjects -join ' - ').ToLower()
        } elseif ($DateKey -match '^(\d{4})(\d{2})(\d{2})$') {
            "$($Matches[1])-$($Matches[2])-$($Matches[3])"
        } else { $DateKey }

        $CleanTitle = $Title -replace "['""]", ""
        $Slug = $DateKey

        # Build gallery data content
        $GalleryContent = ""
        if ($AllGalleryData) {
            $GalleryContent = Format-GalleryData -GalleryData $AllGalleryData -ImageCount $Images.Count
        }

        # Build image markup
        $ImgLines = foreach ($Img in $Images) {
            "<img src={require('./$($Img.Name)').default} alt='$CleanTitle' style={{width:'100%', borderRadius:'6px'}} />"
        }
        $ImgBlock = $ImgLines -join "`n`n"

        # Add card to index — use first image as thumbnail
        $FirstImg = $Images[0].Name
        $IndexCards += @"

<div style={{display:'flex', gap:'12px', alignItems:'flex-start', marginBottom:'1.5rem', padding:'1rem', border:'1px solid var(--card-border)', borderRadius:'10px', background:'var(--card-bg)'}}>
  <a href='/docs/jems-tones/$Slug' style={{flexShrink:0}}><img src={require('./$FirstImg').default} style={{width:'140px', height:'100px', objectFit:'cover', borderRadius:'6px'}} /></a>
  <div><a href='/docs/jems-tones/$Slug' style={{fontWeight:600, fontSize:'1.1rem', textDecoration:'none'}}>${CleanTitle}</a><br/><span style={{color:'var(--ifm-color-secondary)', fontSize:'0.85rem'}}>${($Images.Count)} photos</span></div>
</div>
"@

        $Content = @"
---
title: '$CleanTitle'
---

import GalleryView from '@site/src/components/GalleryView';

$GalleryContent
<GalleryView>

$ImgBlock

</GalleryView>
"@

        [System.IO.File]::WriteAllText((Join-Path $Output "$Slug.mdx"), $Content)
        $PageCount++
        Write-Host "    $($Global:Icons.Check) Gallery Page: $CleanTitle ($($Images.Count) images)" -ForegroundColor Gray
    }

    # Write the index overview page
    $IndexContent = @"
---
id: index
title: 'gallery'
sidebar_label: 'gallery'
sidebar_position: 1
---

import GalleryView from '@site/src/components/GalleryView';

# jems-tones

A curated collection of RAW hobbyist photography. Click any session to view the full gallery.

---

$IndexCards
"@
    [System.IO.File]::WriteAllText((Join-Path $Output "index.mdx"), $IndexContent)
    # Remove old index.md if it exists
    $OldIndex = Join-Path $Output "index.md"
    if (Test-Path $OldIndex) { Remove-Item $OldIndex -Force }

    Write-Host "    $($Global:Icons.Check) Gallery Module: $PageCount session pages generated." -ForegroundColor Green
}

# --- ORCHESTRATION ENGINE ---
function Global:Start-SentinelSync {
    [CmdletBinding()]
    param([string]$ConfigPath = (Join-Path $PSScriptRoot 'Sentinel-Config.yml'))

    $Global:SentinelTimer = [System.Diagnostics.Stopwatch]::StartNew()
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

    # --- OCR PREPROCESSING FOR RECIPES ---
    $OcrLocations = $Global:YamlData.Locations | Where-Object { $_.OCR -eq $true }
    foreach ($loc in $OcrLocations) {
        Write-Host "\n  $($Global:Icons.Arrow) OCR preprocessing for $($loc.Name)" -ForegroundColor Cyan
        Invoke-RecipeOcr -Source $loc.Path
        $ConfigPath = Join-Path $PSScriptRoot 'Sentinel-Config.yml'
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
        $PackageCheck = Join-Path $WebLoc.Path "package.json"
        if ($WebLoc.PurgeWebsite -and (Test-Path $WebLoc.Path)) {
            Write-Host "  $($Global:Icons.Warning) Purging Prep Path: $($WebLoc.Path)" -ForegroundColor Yellow
            
            # Kill any background process locks before attempting folder modifications
            $Port3000Pid = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess
            if ($Port3000Pid) { Stop-Process -Id $Port3000Pid -Force -ErrorAction SilentlyContinue }

            $EmptyTemp = Join-Path $env:TEMP "sentinel_purge_tmp"
            New-Item $EmptyTemp -ItemType Directory -Force | Out-Null
            robocopy $EmptyTemp $WebLoc.Path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
            Remove-Item $WebLoc.Path -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $EmptyTemp -Recurse -Force -ErrorAction SilentlyContinue

            # Auto-reset PurgeWebsite to false so next run is incremental
            $ConfigPath = Join-Path $PSScriptRoot 'Sentinel-Config.yml'
            $ConfigRaw = [System.IO.File]::ReadAllText($ConfigPath)
            $ConfigRaw = $ConfigRaw -replace "'PurgeWebsite': true", "'PurgeWebsite': false"
            [System.IO.File]::WriteAllText($ConfigPath, $ConfigRaw, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  $($Global:Icons.Check) PurgeWebsite auto-reset to false." -ForegroundColor Gray
        }
    
        # 2. SELF-HEALING: Re-scaffold smoothly if package.json is missing or was just purged
        $PackagePath = Join-Path $WebLoc.Path "package.json"
        if (!(Test-Path $PackagePath)) {
            Write-Host "  $($Global:Icons.Error) Engine framework missing or purged. Re-scaffolding..." -ForegroundColor Yellow
            
            if (Test-Path $WebLoc.Path) {
                $EmptyTemp = Join-Path $env:TEMP "sentinel_empty_tmp"
                New-Item $EmptyTemp -ItemType Directory -Force | Out-Null
                robocopy $EmptyTemp $WebLoc.Path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
                Remove-Item $WebLoc.Path -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $EmptyTemp -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $ParentDir = Split-Path $WebLoc.Path
            $FolderName = Split-Path $WebLoc.Path -Leaf
            Push-Location $ParentDir
            npx --yes create-docusaurus@latest $FolderName classic --javascript --skip-install
            Pop-Location

            if (!(Test-Path $PackagePath)) {
                Write-Host "  $($Global:Icons.Error) CRITICAL: Scaffold failed. package.json not found at $PackagePath" -ForegroundColor Red
                return
            }

            # Fix BOM: rewrite package.json without BOM so webpack can parse it smoothly
            $PkgContent = Get-Content $PackagePath -Raw
            [System.IO.File]::WriteAllText($PackagePath, $PkgContent, [System.Text.UTF8Encoding]::new($false))
        }

        # 3. TEMPLATE STAGING: Ensures .md templates exist for Phase 2
        $StagingCoreConfig = Join-Path $WebLoc.Path "core-config"
        if (!(Test-Path $StagingCoreConfig)) { New-Item $StagingCoreConfig -ItemType Directory -Force | Out-Null }
        
        Write-Host "  $($Global:Icons.Check) Staging Templates from Seeds..." -ForegroundColor Cyan
        robocopy (Join-Path $WebLoc.TemplateDir "content-seeds") $StagingCoreConfig /S /E /NFL /NDL /NJH /NJS /nc /ns /np

        # 4. BOILERPLATE CLEANUP: Remove Docusaurus defaults
        $Boilerplate = @("docs/intro.md", "docs/intro.mdx", "docs/tutorial-basics", "docs/tutorial-extras", "blog")
        foreach ($Item in $Boilerplate) {
            $PathToRemove = Join-Path $WebLoc.Path $Item
            if (Test-Path $PathToRemove) { 
                Remove-Item $PathToRemove -Recurse -Force 
                Write-Host "    - Cleaned boilerplate: $Item" -ForegroundColor DarkGray
            }
        }

        # 5. BRANDING: Apply custom configs, CSS, and logo
        if (Test-Path $WebLoc.TemplateDir) {
            Invoke-SentinelBranding -SitePath $WebLoc.Path -TemplateDir $WebLoc.TemplateDir
            Write-SentinelDocusaurusConfig -SitePath $WebLoc.Path -YamlData $Global:YamlData
        }
        
        if (Test-Path (Join-Path $WebLoc.Path "package.json")) {
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

    # Stop Docusaurus before deployment to prevent file lock issues
    Write-Host "  $($Global:Icons.Arrow) Stopping Docusaurus before deployment..." -ForegroundColor Gray
    $Port3000Pid = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess
    if ($Port3000Pid) { Stop-Process -Id $Port3000Pid -Force -ErrorAction SilentlyContinue }
    
    $Port3001Pid = (Get-NetTCPConnection -LocalPort 3001 -State Listen -ErrorAction SilentlyContinue).OwningProcess
    Get-Process node -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $Port3001Pid } | Stop-Process -Force -ErrorAction SilentlyContinue

    # DEPLOY: Mirror to Production
    $DeployTarget = if ($WebLoc.UseNetworkPath -and -not [string]::IsNullOrWhiteSpace($WebLoc.SitePathNetwork)) {
        $WebLoc.SitePathNetwork
    } else {
        $WebLoc.SitePath
    }
    Write-Host "  $($Global:Icons.Check) Deploying to Production: $DeployTarget" -ForegroundColor Green
    robocopy $WebLoc.Path $DeployTarget /MIR /MT:8 /XD node_modules .git /XF sentinel-engine.log /NFL /NDL /NJH /NJS /nc /ns /np

    # Verify node_modules exist in Production
    if (!(Test-Path (Join-Path $DeployTarget "node_modules"))) {
        Write-Host "  $($Global:Icons.Warning) Initializing Production dependencies..." -ForegroundColor Yellow
        robocopy $PrepNM (Join-Path $DeployTarget "node_modules") /E /MT:8 /NFL /NDL /NJH /NJS /nc /ns /np
    }

    # --- PHASE 4: AUTO-LAUNCH ---
    if ($WebLoc.AutoLaunch -or $true) { 
        Start-SentinelProduction -SitePath $DeployTarget
    }

    # Display Final Report
    Write-SentinelReport -Stats $MediaStats -Watch $Global:SentinelTimer -RemoteUrl $Global:YamlData.Settings.RemoteUrl
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
    Write-Host " MISSION COMPLETE: $Global:ToolHeader" -ForegroundColor Green
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
    $Content = @"
label: $Label
link:
  type: generated-index
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

function Global:Get-SentinelBuddy {
    param([System.IO.FileInfo]$Sidecar, [string]$SearchRoot)
    try {
        return Get-ChildItem $SearchRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.BaseName -eq $Sidecar.BaseName -and $_.Extension -ne '.xmp'
        } | Select-Object -First 1
    }
    catch { return $null }
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
        'core-config/index.js'             = "import React from 'react';`nimport {Redirect} from '@docusaurus/router';`nexport default function Home() { return <Redirect to='/docs/index' />; }"
        
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
    
    $SiteName = $YamlData.Settings.SiteName
    if ([string]::IsNullOrWhiteSpace($SiteName)) { 
        $SiteName = "source studio"
        Write-Host "  $($Global:Icons.Warning) No SiteName found in YAML, using default." -ForegroundColor Yellow
    } else {
        $SiteName = $SiteName.ToLower()
    }

    $SiteUrl = if ($YamlData.Settings.RemoteUrl) { $YamlData.Settings.RemoteUrl } else { 'http://localhost:3000' }
    # Strip port for the url field
    $UrlBase = $SiteUrl -replace ':\d+$', ''

    # Build navbar items dynamically from Website locations (skip web-root)
    $Modules = $YamlData.Locations | Where-Object { $_.Role -eq 'Website' -and $_.RootType -ne 'web-root' }
    $NavItems = ""
    foreach ($M in $Modules) {
        $Label = $M.Name.ToLower()
        $Slug  = $M.Name.ToLower().Replace(' ', '-')
        $NavItems += "        {to: '/docs/$Slug', label: '$Label', position: 'left'},`n"
    }
    # Sidebar toggle — visible on all screen sizes via hamburger on mobile
    $NavItems += "        {type: 'docSidebar', sidebarId: 'tutorialSidebar', position: 'right', label: 'all'},`n"

    $ConfigContent = @"
const config = {
  title: '$SiteName',
  tagline: 'sentinel automated wiki',
  url: '$UrlBase',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  favicon: 'img/favicon.ico',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  presets: [
    [
      'classic',
      ({
        docs: {
          sidebarPath: require.resolve('./sidebars.js'),
          breadcrumbs: true,
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig: ({
    navbar: {
      title: '$SiteName',
      hideOnScroll: false,
      items: [
$NavItems      ],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: true,
      },
    },
  }),
};

module.exports = config;
"@

    [System.IO.File]::WriteAllText($ConfigPath, $ConfigContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  $($Global:Icons.Check) Dynamic config updated: $($Modules.Count) nav items generated." -ForegroundColor Gray
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
            Sync-SentinelGallery -Source $loc.Path -Output $OutputPath -TemplateDir $TemplateDir
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

        # Fully autogenerated — index.md is included automatically via sidebar_position
        $SidebarLines += "        {"
        $SidebarLines += "          type: 'autogenerated',"
        $SidebarLines += "          dirName: '$ModuleName',"
        $SidebarLines += "        },"
        $SidebarLines += "      ],"
        $SidebarLines += "    },"
    }

    $SidebarLines += "  ],"
    $SidebarLines += "};"

    # 2. Join and Write using explicit BOM-less UTF-8
    $FinalJS = $SidebarLines -join "`n"
    $SidebarFile = Join-Path $SitePath "sidebars.js"
    [System.IO.File]::WriteAllText($SidebarFile, $FinalJS, [System.Text.UTF8Encoding]::new($false))
}

function Global:Write-SentinelDocsIndex {
    param([string]$SitePath, $YamlData)

    $DocsDir = Join-Path $SitePath "docs"
    if (!(Test-Path $DocsDir)) { New-Item $DocsDir -ItemType Directory -Force | Out-Null }

    $SiteName = if ($YamlData.Settings.SiteName) { $YamlData.Settings.SiteName } else { "Source Studio" }

    # Build module cards from Website locations (skip web-root)
    $Modules = $YamlData.Locations | Where-Object { $_.Role -eq 'Website' -and $_.RootType -ne 'web-root' }

    $Cards = ""
    foreach ($M in $Modules) {
        $Name  = $M.Name
        $Slug  = $Name.ToLower().Replace(' ', '-')
        $Type  = $M.RootType -replace 'web-', ''
        $Type  = (Get-Culture).TextInfo.ToTitleCase($Type)
        $Path  = $M.Path
        $Cards += @"

## [$Name](/docs/$Slug)

**Type:** $Type  
**Source:** ``$Path``

"@
    }

    # Build navigation URLs from web-root location
    $WebRoot = $YamlData.Locations | Where-Object { $_.RootType -eq 'web-root' }
    $NavUrls = ""
    if ($WebRoot -and $WebRoot.NavigationUrls) {
        $NavUrls = "`n---`n`n## Quick Links`n`n"
        foreach ($Url in $WebRoot.NavigationUrls) {
            $Name = $Url.Name
            $UrlStr = $Url.Url
            $NavUrls += "- [$Name]($UrlStr)`n"
        }
        $NavUrls += "`n"
    }

    $Content = @"
---
id: index
title: '$SiteName'
sidebar_label: 'Overview'
sidebar_position: 1
slug: /
---

# $SiteName

Welcome to the Sentinel-generated knowledge base. Below are the active content modules synced into this site.

---
$Cards$NavUrls
---

*Generated by Sentinel Sync — updates automatically on each sync.*
"@

    $IndexPath = Join-Path $DocsDir "index.md"
    [System.IO.File]::WriteAllText($IndexPath, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  $($Global:Icons.Check) Docs index generated: /docs" -ForegroundColor Green
}

# --- SIDECAR DATA EXTRACTION HELPERS ---

function Global:Get-SentinelRecipeData {
    param([string]$ImageDir, [string]$BaseName)
    
    $YmlPath = Join-Path $ImageDir "$BaseName.yml"
    $XmpPath = Join-Path $ImageDir "$BaseName.xmp"
    
    $RecipeData = @{
        Title = ""
        Ingredients = @()
        Instructions = @()
        CookTime = ""
        PrepTime = ""
        Servings = ""
        Tags = @()
    }
    
    # Try YAML sidecar first
    if (Test-Path $YmlPath) {
        try {
            $YamlContent = Get-Content $YmlPath -Raw | ConvertFrom-Yaml
            if ($YamlContent.Recipe) {
                $RecipeData.Title = $YamlContent.Recipe
            }
            if ($YamlContent.Ingredients -and $YamlContent.Ingredients.Count -gt 0) {
                $RecipeData.Ingredients = $YamlContent.Ingredients
            }
            if ($YamlContent.Instructions -and $YamlContent.Instructions.Count -gt 0) {
                $RecipeData.Instructions = $YamlContent.Instructions
            }
            if ($YamlContent.CookTime) {
                $RecipeData.CookTime = $YamlContent.CookTime
            }
            if ($YamlContent.PrepTime) {
                $RecipeData.PrepTime = $YamlContent.PrepTime
            }
            if ($YamlContent.Servings) {
                $RecipeData.Servings = $YamlContent.Servings
            }
            if ($YamlContent.Tags -and $YamlContent.Tags.Count -gt 0) {
                $RecipeData.Tags = $YamlContent.Tags
            }
        } catch {
            Write-Host "    Warning: Could not parse YAML sidecar: $YmlPath" -ForegroundColor Yellow
        }
    }
    
    # Try XMP sidecar for tags/keywords
    if (Test-Path $XmpPath) {
        try {
            $XmpContent = Get-Content $XmpPath -Raw
            if ($XmpContent -match '(?s)<dc:subject>.*?<rdf:Bag>(.*?)</rdf:Bag>') {
                $Matches[1] | Select-String -Pattern '<rdf:li>(.*?)</rdf:li>' -AllMatches |
                    ForEach-Object { $_.Matches } |
                    ForEach-Object {
                        $Tag = $_.Groups[1].Value.Trim()
                        if ($Tag -and $RecipeData.Tags -notcontains $Tag) {
                            $RecipeData.Tags += $Tag
                        }
                    }
            }
        } catch {
            Write-Host "    Warning: Could not parse XMP sidecar: $XmpPath" -ForegroundColor Yellow
        }
    }
    
    return $RecipeData
}

function Global:Get-SentinelGalleryData {
    param([string]$ImageDir, [string]$BaseName)
    
    $XmpPath = Join-Path $ImageDir "$BaseName.xmp"
    
    $GalleryData = @{
        Title = ""
        Camera = ""
        Lens = ""
        Aperture = ""
        ShutterSpeed = ""
        ISO = ""
        Keywords = @()
        DateTaken = ""
    }
    
    if (Test-Path $XmpPath) {
        try {
            $XmpContent = Get-Content $XmpPath -Raw
            
            # Extract title/description
            if ($XmpContent -match '<dc:title>.*?<rdf:Alt>.*?<rdf:li xml:lang="x-default">(.*?)</rdf:li>') {
                $GalleryData.Title = $Matches[1].Trim()
            }
            
            # Extract camera model
            if ($XmpContent -match '<t2m:CameraModelName>(.*?)</t2m:CameraModelName>') {
                $GalleryData.Camera = $Matches[1].Trim()
            }
            
            # Extract lens
            if ($XmpContent -match '<t2m:LensID>(.*?)</t2m:LensID>') {
                $GalleryData.Lens = $Matches[1].Trim()
            }
            
            # Extract aperture
            if ($XmpContent -match '<exif:ApertureValue>(.*?)</exif:ApertureValue>') {
                $GalleryData.Aperture = $Matches[1].Trim()
            }
            
            # Extract shutter speed
            if ($XmpContent -match '<exif:ShutterSpeedValue>(.*?)</exif:ShutterSpeedValue>') {
                $GalleryData.ShutterSpeed = $Matches[1].Trim()
            }
            
            # Extract ISO
            if ($XmpContent -match '<exif:ISOSpeedRatings>.*?<rdf:Bag>(.*?)</rdf:Bag>') {
                $isoMatch = $Matches[1] -match '<rdf:li>(.*?)</rdf:li>'
                if ($isoMatch) {
                    $GalleryData.ISO = $Matches[1].Trim()
                }
            }
            
            # Extract keywords
            if ($XmpContent -match '(?s)<dc:subject>.*?<rdf:Bag>(.*?)</rdf:Bag>') {
                $Matches[1] | Select-String -Pattern '<rdf:li>(.*?)</rdf:li>' -AllMatches |
                    ForEach-Object { $_.Matches } |
                    ForEach-Object {
                        $Keyword = $_.Groups[1].Value.Trim()
                        if ($Keyword -and $GalleryData.Keywords -notcontains $Keyword) {
                            $GalleryData.Keywords += $Keyword
                        }
                    }
            }
            
            # Extract date taken
            if ($XmpContent -match '<xap:CreateDate>(.*?)</xap:CreateDate>') {
                $GalleryData.DateTaken = $Matches[1].Trim()
            }
        } catch {
            Write-Host "    Warning: Could not parse XMP sidecar: $XmpPath" -ForegroundColor Yellow
        }
    }
    
    return $GalleryData
}

function Global:Format-RecipeData {
    param($RecipeData)
    
    $Output = ""
    
    # Recipe title from YAML
    if ($RecipeData.Title) {
        $Output += "# $($RecipeData.Title)`n`n"
    }
    
    # Metadata grid
    $MetaItems = @()
    if ($RecipeData.CookTime) { $MetaItems += "**Cook Time:** $($RecipeData.CookTime)" }
    if ($RecipeData.PrepTime) { $MetaItems += "**Prep Time:** $($RecipeData.PrepTime)" }
    if ($RecipeData.Servings) { $MetaItems += "**Servings:** $($RecipeData.Servings)" }
    
    if ($MetaItems.Count -gt 0) {
        $Output += "<div style={{display:'flex', gap:'2rem', marginBottom:'1.5rem', padding:'1rem', background:'var(--card-bg)', borderRadius:'8px'}}>`n"
        $Output += $MetaItems -join " | "
        $Output += "`n</div>`n`n"
    }
    
    # Ingredients
    if ($RecipeData.Ingredients.Count -gt 0) {
        $Output += "## Ingredients`n`n"
        foreach ($Ing in $RecipeData.Ingredients) {
            $Output += "- $Ing`n"
        }
        $Output += "`n"
    }
    
    # Instructions
    if ($RecipeData.Instructions.Count -gt 0) {
        $Output += "## Instructions`n`n"
        foreach ($Inst in $RecipeData.Instructions) {
            $Output += "$Inst`n`n"
        }
    }
    
    # Tags
    if ($RecipeData.Tags.Count -gt 0) {
        $Output += "## Tags`n`n"
        $Output += ($RecipeData.Tags -join ", ") + "`n"
    }
    
    return $Output
}

function Global:Format-GalleryData {
    param($GalleryData, $ImageCount)
    
    $Output = ""
    
    # Gallery title (from XMP or date-based)
    if ($GalleryData.Title) {
        $Output += "# $($GalleryData.Title)`n`n"
    }
    
    # Camera metadata
    $MetaItems = @()
    if ($GalleryData.Camera) { $MetaItems += "**Camera:** $($GalleryData.Camera)" }
    if ($GalleryData.Lens) { $MetaItems += "**Lens:** $($GalleryData.Lens)" }
    if ($GalleryData.Aperture) { $MetaItems += "**Aperture:** $($GalleryData.Aperture)" }
    if ($GalleryData.ShutterSpeed) { $MetaItems += "**Shutter:** $($GalleryData.ShutterSpeed)" }
    if ($GalleryData.ISO) { $MetaItems += "**ISO:** $($GalleryData.ISO)" }
    if ($GalleryData.DateTaken) { $MetaItems += "**Date:** $($GalleryData.DateTaken)" }
    
    if ($MetaItems.Count -gt 0) {
        $Output += "<div style={{display:'flex', gap:'1.5rem', flexWrap:'wrap', marginBottom:'1.5rem', padding:'0.8rem', background:'var(--card-bg)', borderRadius:'8px', fontSize:'0.9rem', color:'var(--ifm-color-secondary)'}}>`n"
        $Output += $MetaItems -join " | "
        $Output += "`n</div>`n`n"
    }
    
    # Keywords
    if ($GalleryData.Keywords.Count -gt 0) {
        $Output += "## Keywords`n`n"
        $Output += ($GalleryData.Keywords -join ", ") + "`n`n"
    }
    
    return $Output
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
        npm install --no-audit --no-fund
        Pop-Location
    }

    # 2. Safety Cleanup — isolate target process cleanly
    Write-Host "  $($Global:Icons.Arrow) Sweeping stale production processes..." -ForegroundColor Gray
    
    $Port3001Pid = (Get-NetTCPConnection -LocalPort 3001 -State Listen -ErrorAction SilentlyContinue).OwningProcess
    $Port3000Pid = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).OwningProcess
    
    if ($Port3000Pid -and $Port3000Pid -ne $Port3001Pid) { 
        Stop-Process -Id $Port3000Pid -Force -ErrorAction SilentlyContinue 
        Start-Sleep -Seconds 2
    }

    # 3. Run npm start via a hidden PowerShell process
    try {
        Write-Host "  $($Global:Icons.Arrow) Starting npm process..." -ForegroundColor Gray

        $NpmPath = (Get-Command npm -ErrorAction SilentlyContinue).Source
        if (-not $NpmPath) {
            Write-Host "  $($Global:Icons.Error) npm command not found in PATH." -ForegroundColor Red
            return
        }

        $LogFile = Join-Path $SitePath "sentinel-engine.log"
        $LaunchCommand = "Set-Location -Path '$SitePath'; & '$NpmPath' start -- --host 0.0.0.0 --port 3000 2>&1 | Tee-Object -FilePath '$LogFile' -Append"

        $Proc = Start-Process -FilePath "$PSHome\powershell.exe" -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $LaunchCommand -WorkingDirectory $SitePath -WindowStyle Hidden -PassThru
        Write-Host "  $($Global:Icons.Check) Engine process started (PID: $($Proc.Id)). Logging to $LogFile" -ForegroundColor Gray

        Write-Host "  $($Global:Icons.Arrow) Waiting for engine to bind port 3000..." -ForegroundColor Gray
        $maxWait = 60
        $elapsed = 0
        $portReady = $false

        while ($elapsed -lt $maxWait) {
            if ($Proc.HasExited) {
                Write-Host "  $($Global:Icons.Error) Engine process exited early (PID: $($Proc.Id))." -ForegroundColor Red
                if (Test-Path $LogFile) { Get-Content $LogFile -Tail 20 | ForEach-Object { Write-Host "    $_" } }
                return
            }

            $portCheck = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
            if ($portCheck) {
                $portReady = $true
                Write-Host "  $($Global:Icons.Check) Port 3000 is listening!" -ForegroundColor Green
                break
            }

            Start-Sleep -Seconds 2
            $elapsed += 2
            Write-Host "  $($Global:Icons.Arrow) Waiting... ($elapsed/$maxWait sec)" -ForegroundColor DarkGray
        }

        if ($portReady) {
            Write-Host "  $($Global:Icons.Check) Engine is running on port 3000" -ForegroundColor Green
        } else {
            Write-Host "  $($Global:Icons.Warning) Engine not responding on port 3000. Check $LogFile" -ForegroundColor Yellow
            if (Test-Path $LogFile) { Get-Content $LogFile -Tail 20 | ForEach-Object { Write-Host "    $_" } }
        }
    } catch {
        Write-Host "  $($Global:Icons.Error) Failed to start engine: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- AUTO-RUN TRIGGER ---
if ($MyInvocation.MyCommand.Name -eq (Split-Path $PSCommandPath -Leaf) -or $null -eq $MyInvocation.Referrer) {
    Start-SentinelSync
}

function Global:Sync-SentinelShop {
    param($Source, $Output, $TemplateDir)

    Write-Host "`n  $($Global:Icons.Arrow) Processing Pipeline: Millermade Handcrafted" -ForegroundColor Cyan
    Write-Host "    $($Global:Icons.Arrow) Pipeline Path: $Output" -ForegroundColor DarkGray

    # 1. Load the Template
    $TemplateFile = Join-Path $TemplateDir "core-config\shop\hand-crafted.md"
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
            [string]$RawTitle = if ($Data.Product) { $Data.Product } else { $Item.BaseName }
            
            # Clean title: Remove quotes and trim to prevent YAML validation errors
            $CleanTitle = $RawTitle.Trim() -replace "['""]", ""

            # Replace the Primary Title Tags
            $FinalContent = $FinalContent.Replace("{{Product}}", $CleanTitle)
            $FinalContent = $FinalContent.Replace("{{title}}", $CleanTitle)

            # 3. Map all other YAML properties
            foreach ($Prop in $Data.PSObject.Properties) {
                $Key = $Prop.Name
                [string]$Val = if ($null -ne $Prop.Value) { $Prop.Value } else { "" }
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
            [System.IO.File]::WriteAllText($TargetPath, $FinalContent, [System.Text.UTF8Encoding]::new($false))
            
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
        if ($Loc.Role -ne 'Website' -or $Loc.RootType -eq 'web-root') { continue }

        $CleanBase = $TargetWebsitePath.TrimEnd('\')
        if ($CleanBase -notlike "*\docs") {
            $CleanBase = Join-Path $CleanBase "docs"
        }

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

            $DestDir = Split-Path $DestinationPath
            if (!(Test-Path $DestDir)) { New-Item $DestDir -ItemType Directory -Force | Out-Null }

            try {
                $NeedsCopy = $true
                if (Test-Path $DestinationPath) {
                    $DestFile = Get-Item $DestinationPath
                    if ($File.Length -eq $DestFile.Length -and $File.LastWriteTime -le $DestFile.LastWriteTime) {
                        $NeedsCopy = $false
                    }
                }

                if ($NeedsCopy) {
                    Copy-Item -Path $File.FullName -Destination $DestinationPath -Force
                    $Stats.Moved++
                }
                
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

function Global:Invoke-SentinelCsvInclusions {
    param($Locations)

    Write-Host "`nPHASE 1.5: Processing Manifest Inclusions (.include)..." -ForegroundColor Cyan

    foreach ($Loc in $Locations) {
        if (!(Test-Path $Loc.Path)) { continue }

        $IncludeDir = Join-Path $Loc.Path ".include"
        if (!(Test-Path $IncludeDir)) { continue }

        Write-Host "  $($Global:Icons.Arrow) Scanning inclusions for: $($Loc.Name)" -ForegroundColor Gray

        $CsvFiles = Get-ChildItem -Path $IncludeDir -Filter "*.csv" -Recurse
        foreach ($Csv in $CsvFiles) {
            $RelPathFromInclude = $Csv.DirectoryName.Replace($IncludeDir, "").TrimStart('\')
            $TargetFolder = if ($RelPathFromInclude) { Join-Path $Loc.Path $RelPathFromInclude } else { $Loc.Path }
            
            if (!(Test-Path $TargetFolder)) { 
                New-Item $TargetFolder -ItemType Directory -Force | Out-Null 
                Write-Host "    + Created Category: $RelPathFromInclude" -ForegroundColor DarkGray
            }

            $Lines = Get-Content $Csv.FullName | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
            foreach ($Line in $Lines) {
                $SourcePath = $Line.Trim()
                if ($SourcePath -match '^L:\\') {
                    $SourcePath = $SourcePath -replace '^L:\\', '\\LS720DB34C\share\'
                }

                if (Test-Path $SourcePath) {
                    $SourceFile = Get-Item $SourcePath
                    $DestPath = Join-Path $TargetFolder $SourceFile.Name
                    
                    if (!(Test-Path $DestPath)) {
                        Copy-Item $SourceFile.FullName $DestPath -Force
                        Write-Host "      + Included: $($SourceFile.Name)" -ForegroundColor DarkGray
                    }

                    $BaseName = $SourceFile.BaseName
                    $Sidecars = Get-ChildItem -Path $SourceFile.DirectoryName -Filter "$BaseName.*" | Where-Object { $_.Extension -ne $SourceFile.Extension }
                    foreach ($Side in $Sidecars) {
                        $SideDest = Join-Path $TargetFolder $Side.Name
                        if (!(Test-Path $SideDest)) {
                            Copy-Item $Side.FullName $SideDest -Force
                        }
                    }
                } else {
                    Write-Host "      $($Global:Icons.Warning) File not found: $SourcePath" -ForegroundColor Yellow
                }
            }
        }
    }
}

function Global:Invoke-SentinelArchiveSync {
    param($Locations, $FileTypes, $Settings)

    $DryRun   = $Settings.DryRun
    $ImgExts  = $FileTypes.Images
    $RawExts  = $FileTypes.RAWs
    $VidExts  = $FileTypes.Videos
    $AudExts  = $FileTypes.Audio
    $JunkList = $FileTypes.Junk
    $AllMedia = $ImgExts + $RawExts + $VidExts + $AudExts + @('.xmp')

    $PickupLocs   = $Locations | Where-Object { $_.Role -eq 'Pickup' }
    $TimelineLoc  = $Locations | Where-Object { $_.Role -eq 'timeline' } | Select-Object -First 1
    $RawLoc       = $Locations | Where-Object { $_.Role -eq 'RAW_Archive' } | Select-Object -First 1
    $VideoLoc     = $Locations | Where-Object { $_.Role -eq 'Video_Archive' } | Select-Object -First 1
    $AudioLoc     = $Locations | Where-Object { $_.Role -eq 'Audio_Archive' } | Select-Object -First 1
    $ArchiveLocs  = $Locations | Where-Object { $_.Role -match 'Archive|timeline|Hybrid' }

    $Stats = @{ Scanned = 0; Moved = 0; Reunited = 0; Purged = 0; Errors = 0 }

    Write-Host "`nARCHIVE SYNC: Routing Pickup Zones..." -ForegroundColor Cyan

    foreach ($Loc in $PickupLocs) {
        if (!(Test-Path $Loc.Path)) {
            Write-Host "  $($Global:Icons.Warning) OFFLINE: $($Loc.Name)" -ForegroundColor DarkGray
            continue
        }

        $Files = Get-ChildItem -Path $Loc.Path -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $AllMedia -contains $_.Extension.ToLower() }

        $Total = $Files.Count
        $Count = 0

        foreach ($File in $Files) {
            $Stats.Scanned++
            $Count++
            $Ext = $File.Extension.ToLower()

            if (Test-SentinelExclusion -FullPath $File.FullName) { continue }

            $FileDate = if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                try { Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 }
                catch { $File.CreationTime }
            } else { $File.CreationTime }

            $DateFolder = Join-Path $FileDate.ToString('yyyy') $FileDate.ToString('MM MMMM')

            $TargetRoot = $null
            if ($RawExts -contains $Ext)   { $TargetRoot = $RawLoc?.Path }
            elseif ($VidExts -contains $Ext)   { $TargetRoot = $VideoLoc?.Path }
            elseif ($AudExts -contains $Ext)   { $TargetRoot = $AudioLoc?.Path }
            elseif ($ImgExts -contains $Ext -or $Ext -eq '.xmp') { $TargetRoot = $TimelineLoc?.Path }

            if ([string]::IsNullOrWhiteSpace($TargetRoot)) { continue }

            $Destination = Join-Path $TargetRoot $DateFolder
            Write-SentinelOdometer -Tag "ROUTE" -Source $Loc.Name -Path $File.Name -Current $Count -Total $Total

            if (!$DryRun) {
                try {
                    if (!(Test-Path $Destination)) { New-Item $Destination -ItemType Directory -Force | Out-Null }
                    $DestFile = Join-Path $Destination $File.Name
                    if (!(Test-Path $DestFile)) {
                        Move-Item $File.FullName $Destination -Force -ErrorAction Stop
                        $Stats.Moved++
                    }
                } catch {
                    $Stats.Errors++
                }
            }
        }
        Write-Host ""
    }

    if (!$Settings.DisableJunkPurge) {
        Write-Host "  $($Global:Icons.Arrow) Reuniting orphaned sidecars..." -ForegroundColor Gray
        foreach ($Loc in $ArchiveLocs) {
            if (!(Test-Path $Loc.Path)) { continue }
            $Sidecars = Get-ChildItem $Loc.Path -Recurse -File -Filter "*.xmp" -ErrorAction SilentlyContinue
            foreach ($S in $Sidecars) {
                $Buddy = Get-SentinelBuddy -Sidecar $S -SearchRoot $Loc.Path
                if ($Buddy -and $S.DirectoryName -ne $Buddy.DirectoryName -and !$DryRun) {
                    try { Move-Item $S.FullName $Buddy.DirectoryName -Force -ErrorAction Stop; $Stats.Reunited++ }
                    catch { $Stats.Errors++ }
                } elseif (!$Buddy -and $Loc.PurgeOrphan -and !$DryRun) {
                    try { Remove-Item $S.FullName -Force -ErrorAction Stop; $Stats.Purged++ }
                    catch { $Stats.Errors++ }
                }
            }
        }
        Write-Host "    $($Global:Icons.Check) Sidecars: $($Stats.Reunited) reunited, $($Stats.Purged) orphans purged." -ForegroundColor Gray
    }

    if (!$Settings.DisableJunkPurge -and $JunkList) {
        Write-Host "  $($Global:Icons.Arrow) Purging junk files..." -ForegroundColor Gray
        $JunkCount = 0
        foreach ($Loc in $ArchiveLocs) {
            if (!(Test-Path $Loc.Path)) { continue }
            Get-ChildItem $Loc.Path -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $JunkList -contains $_.Name } |
                ForEach-Object {
                    if (!$DryRun) {
                        try { Remove-Item $_.FullName -Force -ErrorAction Stop; $JunkCount++ } catch {}
                    }
                }
        }
        Write-Host "    $($Global:Icons.Check) Junk purged: $JunkCount files." -ForegroundColor Gray
    }

    Write-Host "  $($Global:Icons.Arrow) Sorting unsorted files into month folders..." -ForegroundColor Gray
    $SortedCount = 0
    foreach ($Loc in $ArchiveLocs) {
        if (!(Test-Path $Loc.Path)) { continue }

        Get-ChildItem $Loc.Path -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}$' } |
            ForEach-Object {
                $YearDir = $_.FullName
                $LooseFiles = Get-ChildItem $YearDir -File -ErrorAction SilentlyContinue

                foreach ($File in $LooseFiles) {
                    $Ext = $File.Extension.ToLower()
                    if ($AllMedia -notcontains $Ext) { continue }

                    $FileDate = if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                        try { Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 }
                        catch { $File.CreationTime }
                    } else { $File.CreationTime }

                    $MonthFolder = Join-Path $YearDir $FileDate.ToString('MM MMMM')

                    if (!$DryRun) {
                        try {
                            if (!(Test-Path $MonthFolder)) { New-Item $MonthFolder -ItemType Directory -Force | Out-Null }
                            $Dest = Join-Path $MonthFolder $File.Name
                            if (!(Test-Path $Dest)) {
                                Move-Item $File.FullName $MonthFolder -Force -ErrorAction Stop
                                $SortedCount++
                            }
                        } catch { $Stats.Errors++ }
                    }
                }
            }
    }
    Write-Host "    $($Global:Icons.Check) Sorted $SortedCount files into month folders." -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Check) Archive Sync: Scanned=$($Stats.Scanned) Moved=$($Stats.Moved) Errors=$($Stats.Errors)" -ForegroundColor Green
}

function Global:Invoke-RecipeOcr {
    param([string]$Source)

    if ([string]::IsNullOrWhiteSpace($Source) -or !(Test-Path $Source)) {
        Write-Host "    $($Global:Icons.Warning) OCR source invalid: $Source" -ForegroundColor Yellow
        return
    }

    $ImageFiles = Get-ChildItem -Path $Source -Recurse -File -Include *.jpg, *.jpeg, *.png
    foreach ($Img in $ImageFiles) {
        $YamlPath = [IO.Path]::ChangeExtension($Img.FullName, ".yml")
        if (Test-Path $YamlPath) {
            Write-Host "    $($Global:Icons.Check) OCR skipped (YAML exists): $($Img.Name)" -ForegroundColor Gray
            continue
        }

        $TempTxt = [IO.Path]::GetTempFileName()
        $TessCmd = "tesseract `"$($Img.FullName)`" `"$TempTxt`" -l eng"
        try {
            & $Env:COMSPEC /c $TessCmd | Out-Null
        } catch {
            Write-Host "    $($Global:Icons.Error) Tesseract failed on $($Img.Name): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $RawText = Get-Content -Path $TempTxt -Raw
        Remove-Item $TempTxt -Force

        $YamlObj = @{}
        foreach ($Line in $RawText -split "`n") {
            $trim = $Line.Trim()
            if ($trim -match "^([^:]+):\s*(.+)$") {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                $YamlObj[$key] = $val
            }
        }

        if ($YamlObj.Count -gt 0) {
            $YamlContent = $YamlObj | ConvertTo-Yaml
            [System.IO.File]::WriteAllText($YamlPath, $YamlContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "    $($Global:Icons.Check) OCR generated: $([IO.Path]::GetFileName($YamlPath))" -ForegroundColor Gray
        } else {
            Write-Host "    $($Global:Icons.Warning) OCR produced no parsable key/value for $($Img.Name)" -ForegroundColor Yellow
        }
    }
}
