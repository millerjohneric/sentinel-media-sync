function Get-SentinelRecipeData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RecipeFilePath
    )

    if (-not (Test-Path -Path $RecipeFilePath)) {
        return $null
    }

    $xmpSidecar = [System.IO.Path]::ChangeExtension($RecipeFilePath, '.xmp')
    $ymlSidecar = [System.IO.Path]::ChangeExtension($RecipeFilePath, '.yml')
    if (-not (Test-Path -Path $ymlSidecar)) {
        $ymlSidecar = [System.IO.Path]::ChangeExtension($RecipeFilePath, '.yaml')
    }
    
    $title = $null
    $description = $null
    $rawTags = @()

    if (Test-Path -Path $xmpSidecar) {
        [xml]$xmpXml = Get-Content -Path $xmpSidecar
        
        $nsManager = [System.Xml.XmlNamespaceManager]::new($xmpXml.NameTable)
        $nsManager.AddNamespace('rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#')
        $nsManager.AddNamespace('dc', 'http://purl.org/dc/elements/1.1/')

        $titleNode = $xmpXml.SelectSingleNode('//dc:title/rdf:Alt/rdf:li', $nsManager)
        if ($titleNode) { $title = $titleNode.InnerText }

        $descNode = $xmpXml.SelectSingleNode('//dc:description/rdf:Alt/rdf:li', $nsManager)
        if ($descNode) { $description = $descNode.InnerText }

        $tagNodes = $xmpXml.SelectNodes('//dc:subject/rdf:Bag/rdf:li', $nsManager)
        if ($tagNodes) { $rawTags = $tagNodes | Select-Object -ExpandProperty InnerText }
    }

    $data = @{}
    if (Test-Path -Path $ymlSidecar) {
        try {
            $rawContent = Get-Content -Path $ymlSidecar -Raw
            $parsedData = $rawContent | ConvertFrom-Yaml
            if ($null -ne $parsedData -and ($parsedData -is [hashtable] -or $parsedData -is [System.Collections.IDictionary])) {
                $data = $parsedData
            }
        } catch {
            Write-Host "  $($Global:Icons.Warning) Failed to parse YAML sidecar: $ymlSidecar" -ForegroundColor Yellow
        }
    }

    $resolvedTitle = if ($data.Recipe) { $data.Recipe } elseif ($data.Title) { $data.Title } else { $title }
    $resolvedDesc  = if ($data.Description) { $data.Description } else { $description }
    
    # Normalize Tags into a flat string array
    $tagsInput = if ($data.Tags) { $data.Tags } else { $rawTags }
    $resolvedTags = @()

    if ($tagsInput) {
        foreach ($item in @($tagsInput)) {
            if ($item -is [string] -and $item -match ',') {
                $resolvedTags += $item -split ',\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            } elseif (-not [string]::IsNullOrWhiteSpace($item)) {
                $resolvedTags += $item.ToString().Trim()
            }
        }
    }

    $resolvedIngr = if ($data.Ingredients) { @($data.Ingredients) } else { @() }
    $resolvedInst = if ($data.Instructions) { @($data.Instructions) } elseif ($data.Steps) { @($data.Steps) } else { @() }

    return [PSCustomObject]@{
        Title        = $resolvedTitle
        PrepTime     = $data.PrepTime
        CookTime     = $data.CookTime
        Servings     = $data.Servings
        Description  = $resolvedDesc
        Ingredients  = $resolvedIngr
        Instructions = $resolvedInst
        Tags         = $resolvedTags
    }
}