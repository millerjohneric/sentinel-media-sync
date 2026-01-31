[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "🚀 Preparing to launch Docusaurus on GEEK..." -ForegroundColor Cyan

# Define the mapped drive path
$sitePath = "H:\MakeMeASammich\website"

# Check if the H: drive is accessible
if (Test-Path $sitePath) {
    Set-Location $sitePath
    Write-Host "🏠 Current Location: $(Get-Location)" -ForegroundColor Gray
    Write-Host "🦖 Starting Development Server on Port 3000..." -ForegroundColor Green

    # Launch with network access and specific port
    npx docusaurus start --host 0.0.0.0 --port 3000
}
else {
    Write-Host "❌ Error: Cannot find $sitePath" -ForegroundColor Red
    Write-Host "Ensure H: is mapped to \\home\share and try again." -ForegroundColor Yellow
}