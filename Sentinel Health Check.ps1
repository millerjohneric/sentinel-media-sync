# ==============================================================================
# Sentinel Health Check v1.0
# ==============================================================================
$CorePath = Join-Path $PSScriptRoot 'Sentinel-Core.ps1'
if (Test-Path $CorePath) { . $CorePath }

Import-Module powershell-yaml
$Config = Get-Content (Join-Path $PSScriptRoot 'Sentinel-Config.yml') -Raw | ConvertFrom-Yaml
$Locations = $Config.Locations

Write-Host "`n[HEALTH CHECK] Validating Infrastructure..." -ForegroundColor White
Write-Host "-------------------------------------------------------" -ForegroundColor Gray

$CriticalFail = $false
foreach ($loc in $Locations) {
    $PathExists = Test-Path $loc.Path
    $Status = if ($PathExists) { "ONLINE " } else { "OFFLINE" }
    $Color = if ($PathExists) { "Green" } else { "Red" }
    if (-not $PathExists) { $CriticalFail = $true }

    Write-Host "  [$Status]" -ForegroundColor $Color -NoNewline
    Write-Host " $($loc.Name.PadRight(20)) -> $($loc.Path)" -ForegroundColor Gray
}

Write-Host "-------------------------------------------------------" -ForegroundColor Gray
if ($CriticalFail) { Write-Host "  $($Global:Icons.Warning) Some paths are unreachable." -ForegroundColor Yellow }
else { Write-Host "  $($Global:Icons.Check) All systems nominal." -ForegroundColor Green }