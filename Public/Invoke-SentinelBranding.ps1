function Invoke-SentinelBranding {
    param([string]$SitePath, [string]$TemplateDir)

    Write-Host "`n$($Global:Icons.Check) Injecting Branding & Configs..." -ForegroundColor Cyan

    $Junk = @("static/img/logo.svg", "static/img/favicon.ico", "static/favicon.ico")
    foreach ($j in $Junk) {
        $p = Join-Path $SitePath $j
        if (Test-Path $p) { Remove-Item $p -Force }
    }

    $FavSource = Join-Path $TemplateDir "branding/img/the-source.ico"
    $FavDest = Join-Path $SitePath "static/img/favicon.ico"
    
    if (Test-Path $FavSource) {
        Copy-Item $FavSource $FavDest -Force
        Write-Host "  $($Global:Icons.Check) Deployed custom favicon: the-source.ico" -ForegroundColor Gray
    }

    $SrcCfg = Join-Path $TemplateDir 'core-config'
    if (Test-Path $SrcCfg) {
        Get-ChildItem $SrcCfg -Include *.js, *.json, *.yml | Where-Object { $_.Name -ne 'custom.css' -and $_.Name -ne 'index.js' } | Copy-Item -Destination $SitePath -Force

        $DstCSS = Join-Path $SitePath 'src/css/custom.css'
        if (!(Test-Path (Split-Path $DstCSS))) { New-Item (Split-Path $DstCSS) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'custom.css')) {
            Copy-Item (Join-Path $SrcCfg 'custom.css') $DstCSS -Force
        }

        $DstHome = Join-Path $SitePath 'src/pages/index.js'
        if (!(Test-Path (Split-Path $DstHome))) { New-Item (Split-Path $DstHome) -ItemType Directory -Force | Out-Null }
        if (Test-Path (Join-Path $SrcCfg 'index.js')) {
            Copy-Item (Join-Path $SrcCfg 'index.js') $DstHome -Force
        }
    }

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

    # Define sections to auto-generate index pages for
    $Sections = @(
        @{
            Folder      = 'jems-tones'
            Id          = 'jems-tones-index'
            Title       = 'Gallery'
            Label       = 'Gallery'
            Position    = 3
            Slug        = '/jems-tones-index'
            Header      = 'Gallery'
            Description = 'A curated collection of RAW hobbyist photography.'
            Role        = 'Hybrid_Archive'
            Template    = 'masonry-grid'
        },
        @{
            Folder      = 'recipes'
            Id          = 'recipes-index'
            Title       = 'Recipes'
            Label       = 'Recipes'
            Position    = 4
            Slug        = '/recipes-index'
            Header      = 'Kitchen'
            Description = 'Culinary creations, custom mixes, and favorite dishes.'
            Role        = 'Culinary_Archive'
            Template    = 'grid-list'
        },
        @{
            Folder      = 'shopping'
            Id          = 'shopping-index'
            Title       = 'Shopping'
            Label       = 'Shopping'
            Position    = 5
            Slug        = '/shopping-index'
            Header      = "Gear and Catalog"
            Description = 'Curated gear lists, project hardware, and product reviews.'
            Role        = 'Inventory_Archive'
            Template    = 'grid-list'
        }
    )

    foreach ($sec in $Sections) {
        $SecDir = Join-Path $SitePath "docs/$($sec.Folder)"
        if (!(Test-Path $SecDir)) { New-Item $SecDir -ItemType Directory -Force | Out-Null }
        
        $Content = @"
---
id: $($sec.Id)
title: $($sec.Title)
sidebar_label: $($sec.Label)
sidebar_position: $($sec.Position)
slug: $($sec.Slug)
---

# $($sec.Header)
$($sec.Description)

---
* **Role**: '$($sec.Role)'
* **Template**: '$($sec.Template)'
* **Status**: 'Automated Sync Ready'
"@

        $Content | Out-File -FilePath (Join-Path $SecDir 'index.md') -Encoding utf8 -Force
    }
    Write-Host "  $($Global:Icons.Check) Auto-generated Gallery, Recipes, and Shopping index configurations." -ForegroundColor Green
}