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

    $DocsPath = Join-Path -Path $TargetWebsitePath -ChildPath ($Location.WebSubFolder -replace '^docs[/\\]', 'docs\')
    if (-not (Test-Path -Path $DocsPath)) {
        New-Item -Path $DocsPath -ItemType Directory -Force | Out-Null
    }

    $AllDirs = Get-ChildItem -Path $Source -Recurse -Directory -ErrorAction SilentlyContinue
    $AllSourceDirs = @($Source) + $AllDirs.FullName

    foreach ($CurrentDir in $AllSourceDirs) {
        $RelativeDirPath = $CurrentDir.Substring($Source.Length).TrimStart('\' , '/')
        $TargetDir = if ([string]::IsNullOrWhiteSpace($RelativeDirPath)) { $DocsPath } else { Join-Path -Path $DocsPath -ChildPath $RelativeDirPath }

        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
        }

        $SubIndexPath    = Join-Path -Path $TargetDir -ChildPath 'index.md'
        $SubIndexMdxPath = Join-Path -Path $TargetDir -ChildPath 'index.mdx'
        if (Test-Path -Path $SubIndexMdxPath) { Remove-Item -Path $SubIndexMdxPath -Force }

        if (-not (Test-Path -Path $SubIndexPath)) {
            $FolderName = if ([string]::IsNullOrWhiteSpace($RelativeDirPath)) { $Location.Name } else { Split-Path -Path $CurrentDir -Leaf }
            $DisplayTitle = if ($FolderName) { $FolderName -replace '[-_]', ' ' } else { "Recipes" }
            $UniqueId = if ([string]::IsNullOrWhiteSpace($RelativeDirPath)) { "recipes-index" } else { "recipes-$RelativeDirPath-index" -replace '[/\\]', '-' }
            
            $GroupIndexMarkup = @"
---
id: '$UniqueId'
title: '$DisplayTitle'
---

# $DisplayTitle
"@
            [System.IO.File]::WriteAllText($SubIndexPath, $GroupIndexMarkup, [System.Text.UTF8Encoding]::new($false))
        }

        $LocalFiles = Get-ChildItem -Path $CurrentDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^index\.mdx?$' }
        $ImageMarkup = ""

        foreach ($File in $LocalFiles) {
            $DestFile = Join-Path -Path $TargetDir -ChildPath $File.Name
            Copy-Item -Path $File.FullName -Destination $DestFile -Force

            if ($File.Extension -match '\.(jpg|jpeg|png|gif|webp)$') {
                $ImageMarkup += "`n![$($File.BaseName)](./$($File.Name))`n"
            }
        }

        if ($ImageMarkup -and (Test-Path -Path $SubIndexPath)) {
            $CurrentIndexContent = Get-Content -Path $SubIndexPath -Raw
            if ($CurrentIndexContent -notmatch '## Recipe Media') {
                Add-Content -Path $SubIndexPath -Value "`n## Recipe Media`n$ImageMarkup"
            }
        }
    }

    $AllFiles = Get-ChildItem -Path $DocsPath -Include "*.md", "*.mdx" -Recurse -ErrorAction SilentlyContinue
    foreach ($File in $AllFiles) {
        $Content = Get-Content -Path $File.FullName -Raw
        if ([string]::IsNullOrWhiteSpace($Content)) { continue }
        
        $IsIndex = $File.Name -match '^index\.mdx?$'
        $HasFrontMatter = $Content -match '(?s)^\s*---\r?\n.*?\r?\n---'

        if ($HasFrontMatter) {
            $FrontMatterRaw = [regex]::Match($Content, '(?s)^\s*---\r?\n(.*?)\r?\n---').Groups[1].Value
            $BodyContent     = $Content -replace '(?s)^\s*---\r?\n.*?\r?\n---', ''

            try {
                $YamlData = ConvertFrom-Yaml $FrontMatterRaw
                if ($YamlData -is [hashtable] -or $YamlData -is [System.Collections.IDictionary]) {
                    if ($YamlData.ContainsKey('id')) { $YamlData.Remove('id') }
                    if ($IsIndex -and $YamlData.ContainsKey('slug')) { $YamlData.Remove('slug') }
                    $NewYaml = ConvertTo-Yaml $YamlData
                    $Content = "---`n$NewYaml---`n" + $BodyContent.TrimStart()
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