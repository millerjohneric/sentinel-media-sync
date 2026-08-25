# Ensure powershell-yaml is available at the top of your script
Import-Module powershell-yaml -ErrorAction Stop

function Sync-SentinelShop {
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

    $ymlFiles = Get-ChildItem -Path $shopSource -Filter "*.yml" -Recurse

    foreach ($file in $ymlFiles) {
        $rawYaml = Get-Content -Path $file.FullName -Raw
        $productData = $rawYaml | ConvertFrom-Yaml

        # Escape single quotes for front matter safety
        $title = if ($productData.Title) { $productData.Title -replace "'", "''" } else { "" }
        $price = if ($productData.Price) { $productData.Price -replace "'", "''" } else { "" }
        $sku   = if ($productData.SKU)   { $productData.SKU   -replace "'", "''" } else { "" }

        $cleanBaseName = $file.BaseName
        $isIndex = $cleanBaseName -eq 'index'

        # Mirror source folder structure inside staging directory
        $relativePath = $file.FullName.Substring($shopSource.Length).TrimStart('\' , '/')
        $relativeDir  = [System.IO.Path]::GetDirectoryName($relativePath) -replace '\\', '/'

        $targetDir = if ([string]::IsNullOrWhiteSpace($relativeDir)) { $StagingPath } else { Join-Path -Path $StagingPath -ChildPath $relativeDir }
        if (-not (Test-Path -Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        $targetFile = Join-Path -Path $targetDir -ChildPath "$cleanBaseName.md"
        
        # Omit 'id' and 'slug' on index files to prevent Docusaurus route collisions
        if ($isIndex) {
            $mdContent = @"
---
title: '$title'
price: '$price'
sku: '$sku'
---

# $($productData.Title)

$($productData.Description)
"@
        } else {
            $slug = if ([string]::IsNullOrWhiteSpace($relativeDir)) { "/$cleanBaseName" } else { "/$relativeDir/$cleanBaseName" }
            $mdContent = @"
---
slug: '$slug'
title: '$title'
price: '$price'
sku: '$sku'
---

# $($productData.Title)

$($productData.Description)
"@
        }

        [System.IO.File]::WriteAllText($targetFile, $mdContent, [System.Text.UTF8Encoding]::new($false))
    }
}