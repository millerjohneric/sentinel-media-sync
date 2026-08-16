function Get-SentinelRecipeData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RecipeFilePath
    )

    if (-not (Test-Path -Path $RecipeFilePath)) {
        return $null
    }

    $rawContent = Get-Content -Path $RecipeFilePath -Raw
    $data = $rawContent | ConvertFrom-Yaml

    $xmpSidecar = [System.IO.Path]::ChangeExtension($RecipeFilePath, '.xmp')
    $tags = @()
    if (Test-Path -Path $xmpSidecar) {
        [xml]$xmpXml = Get-Content -Path $xmpSidecar
        $tags = $xmpXml.SelectNodes("//dc:subject/rdf:Bag/rdf:li") | Select-Object -ExpandProperty '#text'
    }

    return [PSCustomObject]@{
        Title       = $data.Title
        PrepTime    = $data.PrepTime
        CookTime    = $data.CookTime
        Ingredients = $data.Ingredients
        Steps       = $data.Steps
        Tags        = $tags
    }
}