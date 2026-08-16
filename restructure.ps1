$ConfigPath = "C:\Source\GEEK\Sentinel\sentinel-media-sync\Sentinel-Config.yml"

if (!(Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found at: $ConfigPath"
    return
}

$RawYaml = Get-Content -Path $ConfigPath -Raw

# Extract settings from the embedded JSON block
$DateFormat  = if ($RawYaml -match '"DateFormat"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }
$ChronoRegex = if ($RawYaml -match '"ChronoRegex"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }

# Determine standard pattern based on ChronoRegex
$DetectedFormat = switch -Regex ($ChronoRegex) {
    '\\d{4}/\\d{2}\\s\\w+' { "YYYY/MM Month (Nested Year/Month Name)" }
    '\\d{4}-\\d{2}-\\d{2}' { "YYYY-MM-DD (ISO Flat Date Standard)" }
    '\\d{4}/\\d{2}'        { "YYYY/MM (Nested Year/Month Number)" }
    '\\d{4}-\\d{2}'        { "YYYY-MM (Flat Year-Month)" }
    default                { "Custom / Unrecognized Pattern" }
}

Write-Host "=== Config File Detection ===" -ForegroundColor Cyan
Write-Host "DateFormat Setting  : $DateFormat" -ForegroundColor White
Write-Host "ChronoRegex Setting : $ChronoRegex" -ForegroundColor White
Write-Host "Original Standard   : $DetectedFormat" -ForegroundColor Yellow

# Inspect physical archive directories on disk to compare
$ArchivePaths = @(
    "L:\Photography_Hobby\_RAW"
)

Write-Host "`n=== Disk Structure Inspection ===" -ForegroundColor Cyan

foreach ($Path in $ArchivePaths) {
    if (!(Test-Path $Path)) { 
        Write-Host "Path unavailable: $Path" -ForegroundColor Red
        continue 
    }

    $Folders = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue

    $YearFolders  = ($Folders | Where-Object { $_.Name -match '^\d{4}$' }).Count
    $MonthNamed   = ($Folders | Where-Object { $_.Name -match '^\d{2}\s[A-Za-z]+$' }).Count
    $IsoFlat      = ($Folders | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' }).Count

    Write-Host "Target Root: $Path" -ForegroundColor White
    Write-Host "  - Top-Level Year Folders (YYYY)   : $YearFolders" -ForegroundColor Gray
    Write-Host "  - Legacy Month Folders (MM Month) : $MonthNamed" -ForegroundColor Gray
    Write-Host "  - Flat Date Folders (YYYY-MM-DD)  : $IsoFlat" -ForegroundColor Gray
}