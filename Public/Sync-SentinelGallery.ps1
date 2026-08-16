function Global:Sync-SentinelGallery {
    param($Source, $Output,$TemplateDir)

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

    # --- Generate index.mdx for every subfolder (thumbnail grid of contents) ---
    $AllOutputDirs = Get-ChildItem -Path $Output -Directory -Recurse
    # Also include the root output dir
    $DirsToIndex = @($AllOutputDirs) + @(Get-Item $Output)

    foreach ($Dir in $DirsToIndex) {
        $DirName  = $Dir.Name
        $Label    = (Get-Culture).TextInfo.ToTitleCase($DirName.Replace('-', ' '))

        # Get subfolders — show as category cards
        $SubDirs  = Get-ChildItem $Dir.FullName -Directory
        # Get images directly in this folder for gallery thumbnails
        $DirImgs  = Get-ChildItem $Dir.FullName -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' -and $_.Name -notmatch '^_thumb_' } | Select-Object -First 12

        $Cards = ""

        # Build the absolute doc path for this folder
        $RelFromOutput = $Dir.FullName.Replace($Output, '').TrimStart('\').Replace('\','/')
        $DocBasePath = if ($RelFromOutput) { "/docs/jems-tones/$RelFromOutput" } else { "/docs/jems-tones" }

        # Subfolder cards with thumbnails
        foreach ($Sub in $SubDirs) {
            $SubLabel = (Get-Culture).TextInfo.ToTitleCase($Sub.Name.Replace('-', ' '))
            $SubSlug  = $Sub.Name
            $SubFullPath = "$DocBasePath/$SubSlug"
            # Count unique gallery sessions
            $AllFiles = Get-ChildItem $Sub.FullName -File -Recurse | Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' -and $_.Name -notmatch '^_thumb_' -and $_.Name -notmatch '^index\.' }
            $SessionCount = ($AllFiles | Group-Object {
                $base = $_.BaseName
                if ($base -match '^\d{8}') { $Matches[0] } else { $base }
            }).Count

            # Pick a RANDOM image from subfolder (recursive)
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
      <div style={{fontSize:'0.78rem', color:'var(--ifm-color-secondary)', marginTop:'2px'}}>$SessionCount sessions</div>
    </div>
  </div>
</a>
"@
        }

        # Gallery cards for files directly in this folder (no subfolders)
        $Sessions = $DirImgs | Group-Object { 
            if ($_.BaseName -match '^(\d{8})') { $Matches[1] } else { 'misc' }
        }

        foreach ($Group in $Sessions) {
            $GroupName = $Group.Name
            $Images    = $Group.Group
            $FirstImg  = $Images[0]

            $RawName = $GroupName -replace '[-_]', ' '
            $GalleryTitle = (Get-Culture).TextInfo.ToTitleCase($RawName.ToLower()) -replace "['""]", ""
            $GalleryFullPath = "$DocBasePath/$GroupName"

            # Pick one thumbnail from the group
            $Thumb = $FirstImg
            $ThumbName = "_thumb_$GroupName$($Thumb.Extension)"
            $ThumbDest = Join-Path $Dir.FullName $ThumbName
            Copy-Item $Thumb.FullName $ThumbDest -Force

            $Cards += @"
<a href='$GalleryFullPath' style={{textDecoration:'none', color:'inherit'}}>
  <div style={{border:'1px solid var(--card-border)', borderRadius:'10px', overflow:'hidden', background:'var(--card-bg)', transition:'transform 0.2s, box-shadow 0.2s'}} onMouseOver={e=>{e.currentTarget.style.transform='translateY(-3px)';e.currentTarget.style.boxShadow='0 6px 20px rgba(0,0,0,0.1)'}} onMouseOut={e=>{e.currentTarget.style.transform='';e.currentTarget.style.boxShadow=''}}>
    <img src={require('./$ThumbName').default} alt='$GalleryTitle' style={{width:'100%', height:'130px', objectFit:'cover'}} />
    <div style={{padding:'0.6rem 0.8rem', fontWeight:500, fontSize:'0.9rem'}}>$GalleryTitle</div>
    <div style={{fontSize:'0.78rem', color:'var(--ifm-color-secondary)', padding:'0 0.6rem 0.6rem'}}>$($Images.Count) photos</div>
  </div>
</a>
"@
        }

        if ($Cards -eq "") { continue }

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

    Write-Host "    $($Global:Icons.Check) Gallery category indexes generated." -ForegroundColor Green
}