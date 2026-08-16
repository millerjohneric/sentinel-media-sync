function Invoke-SentinelWebPipeline {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$LocationConfig
    )

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Error "Template path not found: $TemplatePath"
        return
    }

    $templateContent = Get-Content -Path $TemplatePath -Raw

    if ($templateContent -match '\[RECIPES\]') {
        Write-Verbose "Processing Recipe pipeline..."
        Sync-SentinelRecipes -LocationConfig $LocationConfig
    }

    if ($templateContent -match '\[GALLERY\]') {
        Write-Verbose "Processing Gallery pipeline..."
        Sync-SentinelGallery -LocationConfig $LocationConfig
    }

    if ($templateContent -match '\[SHOP\]') {
        Write-Verbose "Processing Shop pipeline..."
        Sync-SentinelShop -StagingPath $OutputPath -LocationConfig $LocationConfig
    }
}