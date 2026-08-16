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

        $RecipeFiles = Get-ChildItem -Path $Group.FullName -Filter *.md -Recurse -ErrorAction SilentlyContinue
        foreach ($File in $RecipeFiles) {
            $DestFile = Join-Path -Path $GroupDocsPath -ChildPath $File.Name
            Copy-Item -Path $File.FullName -Destination $DestFile -Force
        }
    }

    $AdminMarkup = @"
---
title: Recipe Index
sidebar_position: 1
---

# Recipe Collection
Welcome to the Sentinel recipe archive.
"@

    $IndexPath = Join-Path -Path $DocsPath -ChildPath 'index.md'
    [System.IO.File]::WriteAllText($IndexPath, $AdminMarkup, [System.Text.UTF8Encoding]::new($false))

    $PageCount = 0
    $DirsToIndex = Get-ChildItem -Path $DocsPath -Directory -ErrorAction SilentlyContinue

    foreach ($Dir in $DirsToIndex) {
        $SubDirs = Get-ChildItem -Path $Dir.FullName -Directory -ErrorAction SilentlyContinue
        
        $DocBasePath = if ($SubDirs.Count -gt 0) {
            $Dir.Name
        } else {
            'recipes'
        }

        foreach ($Sub in $SubDirs) {
            $PageCount++
        }
    }

    Write-Host "  $($Global:Icons.Check) Recipes synced. Total pages processed: $PageCount" -ForegroundColor Green
}