Import-Module powershell-yaml -ErrorAction Stop

function Global:Sync-SentinelRecipes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Location,

        [Parameter(Mandatory = $true)]
        [string]$TargetWebsitePath,

        [string]$ImageGroupSeparator = '-.-'
    )

    $Source = $Location.Path
    if (-not $Source -or -not (Test-Path -Path $Source)) {
        Write-Host "  $($Global:Icons.Warning) Recipe source path missing: $Source" -ForegroundColor Yellow
        return
    }

    Write-Host "  $($Global:Icons.Arrow) Processing Recipes from: $Source" -ForegroundColor Cyan

    # Target destination path (maps docs/ subfolders to public/ or docs/)
    $WebSubFolder = if ($Location.WebSubFolder) { $Location.WebSubFolder -replace '^docs[/\\]', 'docs\' } else { 'docs' }
    $DocsPath = Join-Path -Path $TargetWebsitePath -ChildPath $WebSubFolder
    if (-not (Test-Path -Path $DocsPath)) {
        New-Item -Path $DocsPath -ItemType Directory -Force | Out-Null
    }

    $NormalizedSource = (Get-Item $Source).FullName.TrimEnd('\' , '/')
    $AllDirs = Get-ChildItem -Path $NormalizedSource -Recurse -Directory -ErrorAction SilentlyContinue
    $AllSourceDirs = @($NormalizedSource) + ($AllDirs | ForEach-Object { $_.FullName })

    # Helper function to generate valid Docusaurus YAML front matter arrays
    function Get-RecipeFrontMatterString {
        param (
            [string]$Title,
            [string]$CookTime,
            [string]$PrepTime,
            [string]$Servings,
            [array]$Tags
        )
        $cleanTitle = $Title -replace "'", "''"
        $lines = @(
            "---",
            "title: '$cleanTitle'",
            "cookTime: '$CookTime'",
            "prepTime: '$PrepTime'",
            "servings: '$Servings'"
        )

        # Parse tags into strict inline array format: ['Tag1', 'Tag2']
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

        # Clear existing .mdx index files to prevent cross-extension collisions
        $SubIndexPath    = Join-Path -Path $TargetDir -ChildPath 'index.md'
        $SubIndexMdxPath = Join-Path -Path $TargetDir -ChildPath 'index.mdx'
        if (Test-Path -Path $SubIndexMdxPath) { Remove-Item -Path $SubIndexMdxPath -Force }

        $LocalFiles = Get-ChildItem -Path $CurrentDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^index\.mdx?$' }
        $ImageFiles = $LocalFiles | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|gif|webp)$' }

        # Copy local assets to target website path
        foreach ($File in $LocalFiles) {
            $DestFile = Join-Path -Path $TargetDir -ChildPath $File.Name
            Copy-Item -Path $File.FullName -Destination $DestFile -Force
        }

        # Group images by base recipe key using the image group separator
        $GroupedImages = @{}
        foreach ($Img in $ImageFiles) {
            $BaseKey = if ($Img.BaseName -contains $ImageGroupSeparator) {
                ($Img.BaseName -split [regex]::Escape($ImageGroupSeparator))[0]
            } else {
                $Img.BaseName
            }

            if (-not $GroupedImages.ContainsKey($BaseKey)) {
                $GroupedImages[$BaseKey] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            }
            $GroupedImages[$BaseKey].Add($Img)
        }

        $IndexGridMarkup = ""

        # Process grouped recipe pages
        foreach ($RecipeKey in $GroupedImages.Keys) {
            $GroupFiles = $GroupedImages[$RecipeKey]
            $PrimaryImage = $GroupFiles[0]

            $RecipeData = Get-SentinelRecipeData -RecipeFilePath $PrimaryImage.FullName

            $YamlSidecarPath = Join-Path -Path $CurrentDir -ChildPath "$RecipeKey.yml"
            if (-not (Test-Path -Path $YamlSidecarPath)) {
                $YamlSidecarPath = Join-Path -Path $CurrentDir -ChildPath "$RecipeKey.yaml"
            }

            if (Test-Path -Path $YamlSidecarPath) {
                try {
                    $YamlContent = Get-Content -Path $YamlSidecarPath -Raw
                    $SidecarData = ConvertFrom-Yaml $YamlContent
                    if ($null -ne $SidecarData) {
                        if ($SidecarData['Recipe']) { $RecipeData.Title = $SidecarData['Recipe'] }
                        if ($SidecarData['Title']) { $RecipeData.Title = $SidecarData['Title'] }
                        if ($SidecarData['PrepTime']) { $RecipeData.PrepTime = $SidecarData['PrepTime'] }
                        if ($SidecarData['CookTime']) { $RecipeData.CookTime = $SidecarData['CookTime'] }
                        if ($SidecarData['Servings']) { $RecipeData.Servings = $SidecarData['Servings'] }
                        if ($SidecarData['Ingredients']) { $RecipeData.Ingredients = @($SidecarData['Ingredients']) }
                        if ($SidecarData['Instructions']) { $RecipeData.Instructions = @($SidecarData['Instructions']) }
                        if ($SidecarData['Tags']) { 
                            if ($SidecarData['Tags'] -is [string]) {
                                $RecipeData.Tags = @(($SidecarData['Tags'] -split ',\s*'))
                            } else {
                                $RecipeData.Tags = @($SidecarData['Tags'])
                            }
                        }
                        if ($SidecarData['Description']) { $RecipeData.Description = $SidecarData['Description'] }
                    }
                } catch {
                    Write-Host "  $($Global:Icons.Warning) Failed to parse YAML sidecar: $YamlSidecarPath" -ForegroundColor Yellow
                }
            }

            $RecipeTitle  = if ($RecipeData.Title) { $RecipeData.Title } else { $RecipeKey -replace '[-_]', ' ' }
            $PageFileName = "$RecipeKey.md"
            $PagePath     = Join-Path -Path $TargetDir -ChildPath $PageFileName

            # Clear collision page if .mdx exists
            $AltPagePath  = Join-Path -Path $TargetDir -ChildPath "$RecipeKey.mdx"
            if (Test-Path -Path $AltPagePath) { Remove-Item -Path $AltPagePath -Force }

            $DetailImagesMarkup = ""
            foreach ($Img in $GroupFiles) {
                $DetailImagesMarkup += "![$RecipeTitle](./$($Img.Name))<br/>`n`n"
            }

            $IngredientsMarkdown = if ($RecipeData.Ingredients) {
                "## Ingredients`n`n" + (($RecipeData.Ingredients | ForEach-Object { "- $_" }) -join "`n")
            } else { "" }

            $InstructionsMarkdown = if ($RecipeData.Instructions) {
                "## Instructions`n`n" + (($RecipeData.Instructions | ForEach-Object { "1. $_" }) -join "`n")
            } else { "" }

            $ServingsLine = if ($RecipeData.Servings) { "**Servings:** $($RecipeData.Servings)`n`n" } else { "" }

            $prepTimeVal = if ($RecipeData.PrepTime) { $RecipeData.PrepTime } else { "" }
            $cookTimeVal = if ($RecipeData.CookTime) { $RecipeData.CookTime } else { "" }
            $servingsVal = if ($RecipeData.Servings) { $RecipeData.Servings } else { "" }

            $YamlFrontMatter = Get-RecipeFrontMatterString -Title $RecipeTitle -CookTime $cookTimeVal -PrepTime $prepTimeVal -Servings $servingsVal -Tags $RecipeData.Tags

            $DetailPageMarkup = @"
$YamlFrontMatter

# $RecipeTitle

$DetailImagesMarkup
$ServingsLine
$($RecipeData.Description)

$IngredientsMarkdown

$InstructionsMarkdown
"@
            [System.IO.File]::WriteAllText($PagePath, $DetailPageMarkup, [System.Text.UTF8Encoding]::new($false))

            $IndexGridMarkup += "[![$RecipeTitle](./$($PrimaryImage.Name))](./$RecipeKey)`n`n**[$RecipeTitle](./$RecipeKey)**`n`n"
        }

        # Generate index page
        if (-not (Test-Path -Path $SubIndexPath)) {
            $FolderName   = if ([string]::IsNullOrWhiteSpace($RelativeDirPath)) { $Location.Name } else { Split-Path -Path $CurrentDir -Leaf }
            $DisplayTitle = if ($FolderName) { $FolderName -replace '[-_]', ' ' } else { "Recipes" }
            
            $YamlFrontMatter = Get-RecipeFrontMatterString -Title $DisplayTitle -CookTime "" -PrepTime "" -Servings "" -Tags @()

            $GroupIndexMarkup = @"
$YamlFrontMatter

# $DisplayTitle
"@
            [System.IO.File]::WriteAllText($SubIndexPath, $GroupIndexMarkup, [System.Text.UTF8Encoding]::new($false))
        }

        if (-not [string]::IsNullOrWhiteSpace($IndexGridMarkup) -and (Test-Path -Path $SubIndexPath)) {
            $CurrentIndexContent = Get-Content -Path $SubIndexPath -Raw
            if ($CurrentIndexContent -match '(?s)\n## Recipe Index.*') {
                $CurrentIndexContent = $CurrentIndexContent -replace '(?s)\n## Recipe Index.*', ''
            }
            $FinalContent = $CurrentIndexContent.Trim() + "`n`n## Recipe Index`n$IndexGridMarkup"
            [System.IO.File]::WriteAllText($SubIndexPath, $FinalContent, [System.Text.UTF8Encoding]::new($false))
        }
    }

    # Final cleanup pass across generated pages
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
                if ($YamlData -is [hashtable] -or $YamlData -is [System.Collections.IDictionary]) {
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

                    $titleVal = if ($YamlData.ContainsKey('title')) { $YamlData['title'] } else { "Untitled" }
                    $cookVal  = if ($YamlData.ContainsKey('cookTime')) { $YamlData['cookTime'] } else { "" }
                    $prepVal  = if ($YamlData.ContainsKey('prepTime')) { $YamlData['prepTime'] } else { "" }
                    $servVal  = if ($YamlData.ContainsKey('servings')) { $YamlData['servings'] } else { "" }

                    $NewYamlFrontMatter = Get-RecipeFrontMatterString -Title $titleVal -CookTime $cookVal -PrepTime $prepVal -Servings $servVal -Tags $extractedTags
                    $Content = "$NewYamlFrontMatter`n" + $BodyContent.TrimStart()
                }
            } catch {
                $Content = ($Content -replace '(?m)^id:\s*[''"]?.*?\r?\n', '')
                if ($IsIndex) { $Content = ($Content -replace '(?m)^slug:\s*[''"]?.*?\r?\n', '') }
            }
        }

        if ($Content -match '(?m)^(?!export\s+)function\s+') {
            $Content = $Content -replace '(?m)^(?!export\s+)function\s+', 'export function '
        }

        [System.IO.File]::WriteAllText($File.FullName, $Content, [System.Text.UTF8Encoding]::new($false))
    }

    $PageCount = if ($AllFiles) { $AllFiles.Count } else { 0 }
    Write-Host "  $($Global:Icons.Check) Recipes synced. Total pages processed: $PageCount" -ForegroundColor Green
}