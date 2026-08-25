# Ensure powershell-yaml is available at the top of your script
Import-Module powershell-yaml -ErrorAction Stop

function Global:Sync-SentinelGallery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        [string]$Output,

        [Parameter(Mandatory = $false)]
        [string]$TemplateDir
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        if ($null -ne $Config -and $Config.Settings -and $Config.Settings.WebRoot) {
            $Output = Join-Path -Path $Config.Settings.WebRoot -ChildPath 'docs\jems-tones'
        } else {
            Write-Error "Gallery Output path is empty and could not be resolved from Config settings."
            return
        }
    }

    if (-not (Test-Path -Path $Output)) {
        New-Item -Path $Output -ItemType Directory -Force | Out-Null
    }

    Write-Host "`n  $($Global:Icons.Arrow) Processing Pipeline: Gallery" -ForegroundColor Cyan

    # Cleanup legacy index file
    $OldIndex = Join-Path -Path $Output -ChildPath "index.md"
    if (Test-Path -Path $OldIndex) {
        Remove-Item -Path $OldIndex -Force
    }

    $AllOutputDirs = Get-ChildItem -Path $Output -Directory -Recurse -ErrorAction SilentlyContinue
    $DirsToIndex = @($AllOutputDirs) + @(Get-Item -Path $Output)

    foreach ($Dir in $DirsToIndex) {
        if ([string]::IsNullOrEmpty($Output)) { continue }

        $MdxFiles = Get-ChildItem -Path $Dir.FullName -Filter "*.mdx" -ErrorAction SilentlyContinue
        
        foreach ($File in $MdxFiles) {
            $Content = Get-Content -Path $File.FullName -Raw
            $IsIndexFile = $File.Name -eq 'index.mdx'
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
                        if ($IsIndexFile -and $YamlData.ContainsKey('slug')) {
                            $YamlData.Remove('slug')
                        }
                        $NewYaml = ConvertTo-Yaml $YamlData
                        $Content = "---`n$NewYaml---`n" + $BodyContent.TrimStart()
                    }
                } catch {
                    $Content = ($Content -replace '(?m)^id:\s*.*?\r?\n', '')
                    if ($IsIndexFile) {
                        $Content = ($Content -replace '(?m)^slug:\s*[''"]?/[''"]?\r?\n', '')
                    }
                }
            } elseif ($IsIndexFile) {
                $ParentFolder = Split-Path $Dir.FullName -Leaf
                $FrontMatter = @"
---
title: '$ParentFolder'
---

"@
                $Content = $FrontMatter + $Content
            }

            if ($Content -match '(?m)^(?!export\s+)function\s+') {
                $Content = $Content -replace '(?m)^(?!export\s+)function\s+', 'export function '
            }

            [System.IO.File]::WriteAllText($File.FullName, $Content, [System.Text.UTF8Encoding]::new($false))
        }
    }

    Write-Host "     Gallery category indexes generated and patched for MDX." -ForegroundColor Green
}