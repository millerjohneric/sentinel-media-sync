$Tmpl = 'C:\Users\mille\Documents\GitHub\sentinel-media-sync\templates'
$Web  = 'C:\Source_Studio\website'

Write-Host "Injecting Sentinel Branding..." -ForegroundColor Cyan

# 1. Static Assets
$ImgDir = Join-Path $Web "static\img"
if (-not (Test-Path $ImgDir)) { New-Item $ImgDir -ItemType Directory -Force }
Copy-Item "$Tmpl\favicon.ico" (Join-Path $Web "static\") -Force
Copy-Item "$Tmpl\logo.svg" $ImgDir -Force

# 2. UI Components & CSS
Copy-Item "$Tmpl\home-page.js" (Join-Path $Web "src\pages\index.js") -Force
Copy-Item "$Tmpl\custom.css" (Join-Path $Web "src\css\custom.css") -Force

# 3. Dynamic Registry (Required for the Home Page cards)
# If you haven't run Web Gen yet, the home page will be empty.
Write-Host "Branding injected. Please run 'Sentinel Web Gen.ps1' to build your archive pages." -ForegroundColor Green