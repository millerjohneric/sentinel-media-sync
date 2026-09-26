function Global:Get-SentinelGalleryData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    $xmpPath = [System.IO.Path]::ChangeExtension($ImagePath, '.xmp')
    $ymlPath = [System.IO.Path]::ChangeExtension($ImagePath, '.yml')
    if (-not (Test-Path -Path $ymlPath)) {
        $ymlPath = [System.IO.Path]::ChangeExtension($ImagePath, '.yaml')
    }

    $title = $null
    $description = $null
    $camera = 'Unknown'
    $lens = 'Unknown'
    $rawKeywords = @()

    if (Test-Path -Path $xmpPath) {
        [xml]$xmp = Get-Content -Path $xmpPath

        $nsManager = [System.Xml.XmlNamespaceManager]::new($xmp.NameTable)
        $nsManager.AddNamespace('rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#')
        $nsManager.AddNamespace('dc', 'http://purl.org/dc/elements/1.1/')
        $nsManager.AddNamespace('tiff', 'http://ns.adobe.com/tiff/1.0/')
        $nsManager.AddNamespace('aux', 'http://ns.adobe.com/exif/1.0/aux/')

        $cameraNode = $xmp.SelectSingleNode('//tiff:Model', $nsManager)
        if ($cameraNode) { $camera = $cameraNode.InnerText }

        $lensNode = $xmp.SelectSingleNode('//aux:Lens', $nsManager)
        if ($lensNode) { $lens = $lensNode.InnerText }

        $titleNode = $xmp.SelectSingleNode('//dc:title/rdf:Alt/rdf:li', $nsManager)
        if ($titleNode) { $title = $titleNode.InnerText }

        $descNode = $xmp.SelectSingleNode('//dc:description/rdf:Alt/rdf:li', $nsManager)
        if ($descNode) { $description = $descNode.InnerText }

        $tagNodes = $xmp.SelectNodes('//dc:subject/rdf:Bag/rdf:li', $nsManager)
        if ($tagNodes) { $rawKeywords = @($tagNodes | Select-Object -ExpandProperty InnerText) }
    }

    $yamlData = @{}
    if (Test-Path -Path $ymlPath) {
        try {
            $rawYaml = Get-Content -Path $ymlPath -Raw
            $parsedYaml = $rawYaml | ConvertFrom-Yaml
            if ($null -ne $parsedYaml -and ($parsedYaml -is [hashtable] -or $parsedYaml -is [System.Collections.IDictionary])) {
                $yamlData = $parsedYaml
            }
        } catch {
            Write-Host "  $($Global:Icons.Warning) Failed to parse YAML sidecar: $ymlPath" -ForegroundColor Yellow
        }
    }

    $resolvedTitle  = if ($yamlData.Title) { $yamlData.Title } else { $title }
    $resolvedDesc   = if ($yamlData.Description) { $yamlData.Description } else { $description }
    $resolvedCamera = if ($yamlData.Camera) { $yamlData.Camera } else { $camera }
    $resolvedLens   = if ($yamlData.Lens) { $yamlData.Lens } else { $lens }

    # Normalize Keywords/Tags into a guaranteed flat array
    $keywordsInput = if ($yamlData.Keywords) { $yamlData.Keywords } elseif ($yamlData.Tags) { $yamlData.Tags } else { $rawKeywords }
    $resolvedKeywords = [System.Collections.Generic.List[string]]::new()

    if ($keywordsInput) {
        foreach ($item in @($keywordsInput)) {
            if ($null -ne $item) {
                $strVal = $item.ToString().Trim()
                if ($strVal -match ',') {
                    foreach ($subTag in ($strVal -split ',\s*')) {
                        if (-not [string]::IsNullOrWhiteSpace($subTag)) {
                            $resolvedKeywords.Add($subTag.Trim())
                        }
                    }
                } elseif (-not [string]::IsNullOrWhiteSpace($strVal)) {
                    $resolvedKeywords.Add($strVal)
                }
            }
        }
    }

    return [PSCustomObject]@{
        FileName    = Split-Path -Leaf $ImagePath
        Title       = $resolvedTitle
        Description = $resolvedDesc
        Camera      = $resolvedCamera
        Lens        = $resolvedLens
        Keywords    = @($resolvedKeywords)
    }
}