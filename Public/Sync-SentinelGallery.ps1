Import-Module powershell-yaml -ErrorAction Stop

function Global:Sync-SentinelGallery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Location,

        [Parameter(Mandatory = $true)]
        [string]$TargetWebsitePath
    )

    $Source = $Location.Path
    if (-not $Source -or -not (Test-Path -Path $Source)) {
        Write-Host "  $($Global:Icons.Warning) Gallery source path missing: $Source" -ForegroundColor Yellow
        return
    }

    Write-Host "  $($Global:Icons.Arrow) Processing Gallery from: $Source" -ForegroundColor Cyan

    $WebSubFolder = if ($Location.WebSubFolder) { $Location.WebSubFolder -replace '^docs[/\\]', 'docs\' } else { 'docs' }
    $DocsPath = Join-Path -Path $TargetWebsitePath -ChildPath $WebSubFolder
    if (-not (Test-Path -Path $DocsPath)) {
        New-Item -Path $DocsPath -ItemType Directory -Force | Out-Null
    }

    $NormalizedSource = (Get-Item $Source).FullName.TrimEnd('\' , '/')
    $AllDirs = Get-ChildItem -Path $NormalizedSource -Recurse -Directory -ErrorAction SilentlyContinue
    $AllSourceDirs = @($NormalizedSource) + ($AllDirs | ForEach-Object { $_.FullName })

    # Helper function to generate valid Docusaurus front matter string
    function Get-GalleryFrontMatterString {
        param (
            [string]$Title,
            [array]$Tags
        )
        $cleanTitle = $Title -replace "'", "''"
        $lines = @(
            "---",
            "title: '$cleanTitle'"
        )

        $flatTags = @()
        if ($Tags) {
            foreach ($t in $Tags) {
                if ($null -ne $t) {
                    $strVal = $t.ToString().Trim()
                    if ($strVal -match ',') {
                        $flatTags += ($strVal -split ',\s*')
                    } elseif ($strVal) {
                        $flatTags += $strVal
                    }
                }
            }
        }

        if ($flatTags.Count -gt 0) {
            $formattedItems = $flatTags | ForEach-Object {
                $tagStr = $_ -replace "'", "''"
                "'$tagStr'"
            }
            $lines += "tags: [" + ($formattedItems -join ", ") + "]"
        } else {
            $lines += "tags: []"
        }

        $lines += "---"
        return ($lines -join "`n")
    }

    foreach ($CurrentDir in $AllSourceDirs) {
        $RelativeDirPath = ""
        if ($CurrentDir.Length -gt $NormalizedSource.Length) {
            $RelativeDirPath = $CurrentDir.Substring($NormalizedSource.Length).TrimStart('\' , '/')
        }

        $TargetDir = if ([string]::IsNullOrWhiteSpace($RelativeDirPath)) { $DocsPath } else { Join-Path -Path $DocsPath -ChildPath $RelativeDirPath }

        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
        }

        $SubIndexPath    = Join-Path -Path $TargetDir -ChildPath 'index.md'
        $SubIndexMdxPath = Join-Path -Path $TargetDir -ChildPath 'index.mdx'
        if (Test-Path -Path $SubIndexMdxPath) { Remove-Item -Path $SubIndexMdxPath -Force }

        $LocalFiles = Get-ChildItem -Path $CurrentDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^index\.mdx?$' }
        $ImageFiles = $LocalFiles | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|gif|webp)$' }

        # Copy assets to target web directory
        foreach ($File in $LocalFiles) {
            $DestFile = Join-Path -Path $TargetDir -ChildPath $File.Name
            Copy-Item -Path $File.FullName -Destination $DestFile -Force
        }

        $FolderName = if ([string]::IsNullOrWhiteSpace($RelativeDirPath)) { $Location.Name } else { Split-Path -Path $CurrentDir -Leaf }
        $DisplayTitle = if ($FolderName) { $FolderName -replace '[-_]', ' ' } else { "Gallery" }

        # Scenario 1: Subfolder containing exactly 1 image
        if ($ImageFiles.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($RelativeDirPath)) {
            $SingleImage = $ImageFiles[0]
            
            # Retrieve base metadata from image/XMP
            $meta = Get-SentinelGalleryData -ImagePath $SingleImage.FullName

            # Check for a sidecar YAML file
            $YamlSidecarPath = [System.IO.Path]::ChangeExtension($SingleImage.FullName, '.yml')
            if (-not (Test-Path -Path $YamlSidecarPath)) {
                $YamlSidecarPath = [System.IO.Path]::ChangeExtension($SingleImage.FullName, '.yaml')
            }

            $tagsArray = @()
            if ($meta.Keywords) { $tagsArray += $meta.Keywords }

            if (Test-Path -Path $YamlSidecarPath) {
                try {
                    $YamlContent = Get-Content -Path $YamlSidecarPath -Raw
                    $SidecarData = ConvertFrom-Yaml $YamlContent
                    if ($null -ne $SidecarData) {
                        if ($SidecarData['Recipe']) { $meta.Title = $SidecarData['Recipe'] }
                        if ($SidecarData['Title']) { $meta.Title = $SidecarData['Title'] }
                        if ($SidecarData['Description']) { $meta.Description = $SidecarData['Description'] }
                        if ($SidecarData['PrepTime']) { $meta.PrepTime = $SidecarData['PrepTime'] }
                        if ($SidecarData['CookTime']) { $meta.CookTime = $SidecarData['CookTime'] }
                        if ($SidecarData['Servings']) { $meta.Servings = $SidecarData['Servings'] }
                        if ($SidecarData['Tags']) { 
                            if ($SidecarData['Tags'] -is [string]) {
                                $tagsArray = @(($SidecarData['Tags'] -split ',\s*'))
                            } else {
                                $tagsArray = @($SidecarData['Tags'])
                            }
                        }
                        if ($SidecarData['Camera']) { $meta.Camera = $SidecarData['Camera'] }
                        if ($SidecarData['Lens']) { $meta.Lens = $SidecarData['Lens'] }
                    }
                } catch {
                    Write-Host "  $($Global:Icons.Warning) Failed to parse YAML sidecar: $YamlSidecarPath" -ForegroundColor Yellow
                }
            }

            $itemTitle = if ($meta.Title) { $meta.Title } else { $DisplayTitle }

            $YamlFrontMatter = Get-GalleryFrontMatterString -Title $itemTitle -Tags $tagsArray

            $SinglePageMarkup = @"
$YamlFrontMatter

# $itemTitle

![$itemTitle](./$($SingleImage.Name))

$($meta.Description)

*_Shot with $($meta.Camera) ($($meta.Lens))*_
"@
            [System.IO.File]::WriteAllText($SubIndexPath, $SinglePageMarkup, [System.Text.UTF8Encoding]::new($false))
        }
        # Scenario 2: Main Index or Subfolder with multiple images
        else {
            $ImageMarkup = ""
            foreach ($File in $ImageFiles) {
                $meta = Get-SentinelGalleryData -ImagePath $File.FullName

                $YamlSidecarPath = [System.IO.Path]::ChangeExtension($File.FullName, '.yml')
                if (-not (Test-Path -Path $YamlSidecarPath)) {
                    $YamlSidecarPath = [System.IO.Path]::ChangeExtension($File.FullName, '.yaml')
                }

                if (Test-Path -Path $YamlSidecarPath) {
                    try {
                        $YamlContent = Get-Content -Path $YamlSidecarPath -Raw
                        $SidecarData = ConvertFrom-Yaml $YamlContent
                        if ($null -ne $SidecarData) {
                            if ($SidecarData['Recipe']) { $meta.Title = $SidecarData['Recipe'] }
                            if ($SidecarData['Title']) { $meta.Title = $SidecarData['Title'] }
                            if ($SidecarData['Description']) { $meta.Description = $SidecarData['Description'] }
                        }
                    } catch {}
                }

                $displayAlt = if ($meta.Title) { $meta.Title } else { $File.BaseName }

                $ImageMarkup += "`n### $displayAlt`n`n![$displayAlt](./$($File.Name))`n"

                if ($meta.Description) {
                    $ImageMarkup += "`n$($meta.Description)`n"
                }

                if ($meta.Camera -ne 'Unknown' -or $meta.Lens -ne 'Unknown') {
                    $ImageMarkup += "`n*_Shot with $($meta.Camera) ($($meta.Lens))*_\n"
                }
            }

            if (-not (Test-Path -Path $SubIndexPath)) {
                $YamlFrontMatter = Get-GalleryFrontMatterString -Title $DisplayTitle -Tags @()

                $GroupIndexMarkup = @"
$YamlFrontMatter

# $DisplayTitle
"@
                [System.IO.File]::WriteAllText($SubIndexPath, $GroupIndexMarkup, [System.Text.UTF8Encoding]::new($false))
            }

            if (-not [string]::IsNullOrWhiteSpace($ImageMarkup)) {
                $CurrentIndexContent = Get-Content -Path $SubIndexPath -Raw
                if ($CurrentIndexContent -match '(?s)\n## Gallery.*') {
                    $CurrentIndexContent = $CurrentIndexContent -replace '(?s)\n## Gallery.*', ''
                }
                $FinalContent = $CurrentIndexContent.Trim() + "`n`n## Gallery`n$ImageMarkup"
                [System.IO.File]::WriteAllText($SubIndexPath, $FinalContent, [System.Text.UTF8Encoding]::new($false))
            }
        }
    }

    # Clean up Front-Matter YAML across generated pages
    $AllFiles = Get-ChildItem -Path $DocsPath -Include "*.md", "*.mdx" -Recurse -ErrorAction SilentlyContinue
    foreach ($File in $AllFiles) {
        $Content = Get-Content -Path $File.FullName -Raw
        if ([string]::IsNullOrWhiteSpace($Content)) { continue }

        $IsIndex = $File.Name -match '^index\.mdx?$'
        $HasFrontMatter = $Content -match '(?s)^\s*---\r?\n.*?\r?\n---'

        if ($HasFrontMatter) {
            $FrontMatterMatch = [regex]::Match($Content, '(?s)^\s*---\r?\n(.*?)\r?\n---')
            $FrontMatterRaw   = $FrontMatterMatch.Groups[1].Value
            $BodyContent      = $Content -replace '(?s)^\s*---\r?\n.*?\r?\n---', ''

            try {
                $YamlData = ConvertFrom-Yaml $FrontMatterRaw
                if ($null -ne $YamlData -and ($YamlData -is [hashtable] -or $YamlData -is [System.Collections.IDictionary])) {
                    if ($YamlData.ContainsKey('id')) { $YamlData.Remove('id') }
                    if ($IsIndex -and $YamlData.ContainsKey('slug')) { $YamlData.Remove('slug') }
                    
                    $extractedTags = @()
                    if ($YamlData.ContainsKey('tags')) {
                        if ($YamlData['tags'] -is [string]) {
                            $extractedTags = @(($YamlData['tags'] -split ',\s*'))
                        } elseif ($YamlData['tags'] -is [array] -or $YamlData['tags'] -is [System.Collections.IList]) {
                            foreach ($t in $YamlData['tags']) {
                                if ($t -is [string] -and $t -match ',') {
                                    $extractedTags += $t -split ',\s*'
                                } else {
                                    $extractedTags += $t
                                }
                            }
                        }
                    }

                    $titleVal = if ($YamlData.ContainsKey('title')) { $YamlData['title'] } else { "Gallery" }
                    $NewYamlFrontMatter = Get-GalleryFrontMatterString -Title $titleVal -Tags $extractedTags
                    $Content = "$NewYamlFrontMatter`n" + $BodyContent.TrimStart()
                }
            } catch {
                $Content = ($Content -replace '(?m)^id:\s*[''"]?.*?\r?\n', '')
                if ($IsIndex) { $Content = ($Content -replace '(?m)^slug:\s*[''"]?.*?\r?\n', '') }
            }
        }

        [System.IO.File]::WriteAllText($File.FullName, $Content, [System.Text.UTF8Encoding]::new($false))
    }

    $PageCount = if ($AllFiles) { $AllFiles.Count } else { 0 }
    Write-Host "  $($Global:Icons.Check) Gallery synced. Total pages processed: $PageCount" -ForegroundColor Green
}