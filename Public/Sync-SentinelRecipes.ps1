# Ensure powershell-yaml is available at the top of your script
Import-Module powershell-yaml -ErrorAction Stop

function Global:Sync-SentinelRecipes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Location,

        [Parameter(Mandatory = $true)]
        [string]$TargetWebsitePath
    )

    $Source = $Location.Path
    if (-not (Test-Path -Path $Source)) {
        Write-Host "  $($Global:Icons.Warning) Recipe source path missing: $Source" -ForegroundColor Yellow
        return
    }

    Write-Host "  $($Global:Icons.Arrow) Processing Recipes from: $Source" -ForegroundColor Cyan

    $DocsPath = Join-Path -Path $TargetWebsitePath -ChildPath 'docs\recipes'
    if (-not (Test-Path -Path $DocsPath)) {
        New-Item -Path $DocsPath -ItemType Directory -Force | Out-Null
    }

    $Groups = Get-ChildItem -Path $Source -Directory -ErrorAction SilentlyContinue

    foreach ($Group in $Groups) {
        $GroupDocsPath = Join-Path -Path $DocsPath -ChildPath $Group.Name
        if (-not (Test-Path -Path $GroupDocsPath)) {
            New-Item -Path $GroupDocsPath -ItemType Directory -Force | Out-Null
        }

        $RecipeFiles = Get-ChildItem -Path $Group.FullName -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
        foreach ($File in $RecipeFiles) {
            $DestFile = Join-Path -Path $GroupDocsPath -ChildPath $File.Name
            Copy-Item -Path $File.FullName -Destination $DestFile -Force
        }
    }

    # 1. Ensure Root Index File Exists
    $RootIndexPath = Join-Path -Path $DocsPath -ChildPath 'index.md'
    if (-not (Test-Path -Path $RootIndexPath)) {
        $AdminMarkup = @"
---
title: 'Recipe Index'
sidebar_position: 1
---

# Recipe Collection
Welcome to the Sentinel recipe archive.
"@
        [System.IO.File]::WriteAllText($RootIndexPath, $AdminMarkup, [System.Text.UTF8Encoding]::new($false))
    }

    # 2. Auto-create subfolder index files if missing
    $AllDirectories = Get-ChildItem -Path $DocsPath -Directory -Recurse -ErrorAction SilentlyContinue
    foreach ($Dir in $AllDirectories) {
        $SubIndexPath = Join-Path -Path $Dir.FullName -ChildPath 'index.md'
        $SubIndexMdxPath = Join-Path -Path $Dir.FullName -ChildPath 'index.mdx'

        if (-not (Test-Path -Path $SubIndexPath) -and -not (Test-Path -Path $SubIndexMdxPath)) {
            $DirTitle = $Dir.Name -replace '[-_]', ' '
            $DirIndexMarkup = @"
---
title: '$DirTitle'
---

# $DirTitle
"@
            [System.IO.File]::WriteAllText($SubIndexPath, $DirIndexMarkup, [System.Text.UTF8Encoding]::new($false))
        }
    }

    # 3. Patch Front Matter & JS Functions Across All MD/MDX Files
    $AllMdxFiles = Get-ChildItem -Path $DocsPath -Include "*.mdx", "*.md" -Recurse -ErrorAction SilentlyContinue
    foreach ($MdxFile in $AllMdxFiles) {
        $Content = Get-Content -Path $MdxFile.FullName -Raw
        $HasFrontMatter = $Content -match '(?s)^\s*---\r?\n.*?\r?\n---'

        if ($HasFrontMatter) {
            $FrontMatterRaw = [regex]::Match($Content, '(?s)^\s*---\r?\n(.*?)\r?\n---').Groups[1].Value
            $BodyContent = $Content -replace '(?s)^\s*---\r?\n.*?\r?\n---', ''

            try {
                $YamlData = ConvertFrom-Yaml $FrontMatterRaw
                if ($YamlData -is [hashtable] -or $YamlData -is [System.Collections.IDictionary]) {
                    if ($YamlData.ContainsKey('id')) {
                        $YamlData.Remove('id')
                    }
                    $NewYaml = ConvertTo-Yaml $YamlData
                    $Content = "---`n$NewYaml---`n" + $BodyContent.TrimStart()
                }
            } catch {
                $Content = ($Content -replace '(?m)^id:\s*[''"]?.*?\r?\n', '')
            }
        }

        if ($Content -match '(?m)^(?!export\s+)function\s+') {
            $Content = $Content -replace '(?m)^(?!export\s+)function\s+', 'export function '
        }

        [System.IO.File]::WriteAllText($MdxFile.FullName, $Content, [System.Text.UTF8Encoding]::new($false))
    }

    $PageCount = $AllMdxFiles.Count
    Write-Host "  $($Global:Icons.Check) Recipes synced. Total pages processed: $PageCount" -ForegroundColor Green
}