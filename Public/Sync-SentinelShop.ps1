Import-Module powershell-yaml -ErrorAction Stop

function Global:Sync-SentinelShop {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$StagingPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$LocationConfig
    )

    $shopSource = $LocationConfig.ShopPath
    if (-not (Test-Path -Path $shopSource)) {
        Write-Warning "Shop source path does not exist: $shopSource"
        return
    }

    if (-not (Test-Path -Path $StagingPath)) {
        New-Item -Path $StagingPath -ItemType Directory -Force | Out-Null
    }

    $RootMdx = Join-Path -Path $StagingPath -ChildPath 'index.mdx'
    if (Test-Path -Path $RootMdx) { Remove-Item -Path $RootMdx -Force }

    $ymlFiles = Get-ChildItem -Path $shopSource -Filter "*.yml" -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $ymlFiles) {
        $rawYaml = Get-Content -Path $file.FullName -Raw
        $productData = $rawYaml | ConvertFrom-Yaml

        $cleanBaseName = $file.BaseName
        $isIndex = $cleanBaseName -eq 'index'

        $rawTitle = $productData.Title
        if (-not $rawTitle) { $rawTitle = $productData.title }
        if (-not $rawTitle) { $rawTitle = $productData.name }
        if (-not $rawTitle) { $rawTitle = $productData.Name }
        if (-not $rawTitle) { $rawTitle = ($cleanBaseName -replace '[-_]', ' ') }

        $title = $rawTitle -replace "'", "''"

        $rawPrice = if ($productData.Price) { $productData.Price } else { $productData.price }
        $price = if ($rawPrice) { $rawPrice -replace "'", "''" } else { "" }

        $rawSku = if ($productData.SKU) { $productData.SKU } else { $productData.sku }
        $sku = if ($rawSku) { $rawSku -replace "'", "''" } else { "" }

        $description = if ($productData.Description) { $productData.Description } else { $productData.description }

        $relativePath = $file.FullName.Substring($shopSource.Length).TrimStart('\' , '/')
        $relativeDir  = [System.IO.Path]::GetDirectoryName($relativePath) -replace '\\', '/'

        $targetDir = if ([string]::IsNullOrWhiteSpace($relativeDir)) { $StagingPath } else { Join-Path -Path $StagingPath -ChildPath $relativeDir }
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        if ($isIndex) {
            $conflictingMdx = Join-Path -Path $targetDir -ChildPath 'index.mdx'
            if (Test-Path -Path $conflictingMdx) {
                Remove-Item -Path $conflictingMdx -Force
            }
        }

        $targetFile = Join-Path -Path $targetDir -ChildPath "$cleanBaseName.md"

        if ($isIndex) {
            $mdContent = @"
---
id: 'shop-index'
title: '$title'
price: '$price'
sku: '$sku'
---

# $rawTitle

$description
"@
        } else {
            $slugPath = if ([string]::IsNullOrWhiteSpace($relativeDir)) { $cleanBaseName } else { "$relativeDir/$cleanBaseName" }
            $uniqueId = "shop-$slugPath" -replace '[/\\]', '-'
            $slug = "/millermade-handcrafted/$slugPath"
            $mdContent = @"
---
id: '$uniqueId'
slug: '$slug'
title: '$title'
price: '$price'
sku: '$sku'
---

# $rawTitle

$description
"@
        }

        [System.IO.File]::WriteAllText($targetFile, $mdContent, [System.Text.UTF8Encoding]::new($false))
    }

    $RootIndexMd = Join-Path -Path $StagingPath -ChildPath 'index.md'
    if (-not (Test-Path -Path $RootIndexMd)) {
        $DefaultIndex = @"
---
id: 'shop-root-index'
title: 'Shop Catalog'
sidebar_position: 1
---

# Shop Catalog
Welcome to our collection.
"@
        [System.IO.File]::WriteAllText($RootIndexMd, $DefaultIndex, [System.Text.UTF8Encoding]::new($false))
    }
    $TotalProcessed = (Get-ChildItem -Path $StagingPath -Include "*.md" -Recurse).Count
    Write-Host "  $($Global:Icons.Check) Shop synced. Total pages generated: $TotalProcessed" -ForegroundColor Green
}