$DocsPath = 'C:\Source_Studio\website\docs'
Get-ChildItem -Path $DocsPath -Include '*.md', '*.mdx' -Recurse | ForEach-Object {
    $content = Get-Content -Path $_.FullName -Raw
    $isIndex = $_.Name -match '^index\.mdx?$'
    
    # Strip invalid slash-containing id parameters
    $cleanContent = $content -replace '(?m)^id:\s*[''"]?.*?/.*?[''"]?\r?\n', ''
    
    # Strip explicit slug parameters on index files to prevent route collisions
    if ($isIndex) {
        $cleanContent = $cleanContent -replace '(?m)^slug:\s*[''"]?.*?[''"]?\r?\n', ''
    }
    
    if ($cleanContent -ne $content) {
        [System.IO.File]::WriteAllText($_.FullName, $cleanContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Cleaned index front-matter: $($_.FullName)" -ForegroundColor Green
    }
}