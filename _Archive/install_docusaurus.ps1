# ==============================================================================
# Docusaurus Site Initializer (Sentinel Sync Companion)
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# 1. Setup Absolute Paths
$ParentPath = "C:\Source_Studio"
$SiteFolderName = "website"
$FullSitePath = "C:\Source_Studio\website"

Write-Host "--- Starting Docusaurus installation for: $FullSitePath ---" -ForegroundColor Cyan

# 2. Prerequisites Check
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Node.js/NPM not found. Please install Node.js." -ForegroundColor Red
    exit
}

# 3. Clean Slate Logic
if (Test-Path $FullSitePath) {
    Write-Host "Target directory exists. Removing it for a fresh install..." -ForegroundColor Yellow
    Remove-Item -Path $FullSitePath -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $ParentPath)) {
    Write-Host "Creating parent directory: $ParentPath" -ForegroundColor Gray
    New-Item -ItemType Directory -Path $ParentPath -Force | Out-Null
}

# 4. Initialize Docusaurus
# We run this specifically FROM the parent path
Set-Location -Path $ParentPath
Write-Host "Scaffolding classic Docusaurus template..." -ForegroundColor Yellow

# Force npx to use the latest version and create the folder
npx --yes create-docusaurus@latest $SiteFolderName classic --skip-install

# 5. Dependency Installation
if (Test-Path $FullSitePath) {
    # Move INTO the new website folder before running npm
    Set-Location -Path $FullSitePath

    Write-Host "Installing dependencies in $FullSitePath..." -ForegroundColor Yellow
    npm install

    if (Test-Path (Join-Path $FullSitePath "node_modules")) {
        Write-Host "Installation successful!" -ForegroundColor Green
    } else {
        Write-Host "npm install failed to create node_modules." -ForegroundColor Red
    }
} else {
    Write-Host "Scaffolding failed. Folder was not created." -ForegroundColor Red
    exit
}

# 6. Launch
Write-Host "Launching Development Server..." -ForegroundColor Green
npx docusaurus start --host 0.0.0.0 --port 3000