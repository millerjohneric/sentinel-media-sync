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

    $ymlFiles = Get-ChildItem -Path $shopSource -Filter "*.yml" -Recurse

    foreach ($file in $ymlFiles) {
        $rawYaml = Get-Content -Path $file.FullName -Raw
        $productData = $rawYaml | ConvertFrom-Yaml

        $targetFile = Join-Path -Path $StagingPath -ChildPath "$($file.BaseName).md"
        
        $mdContent = @"
---
title: '$($productData.Title)'
price: '$($productData.Price)'
sku: '$($productData.SKU)'
---

# $($productData.Title)

$($productData.Description)
"@

        Set-Content -Path $targetFile -Value $mdContent -Encoding UTF8
    }
}