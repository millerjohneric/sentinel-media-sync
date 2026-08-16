$QuarantinePath = "L:\f_d_up"
$SourcePath     = "L:\Photo_Archive\timeline"

if (!(Test-Path $QuarantinePath)) {
    New-Item -ItemType Directory -Path $QuarantinePath -Force | Out-Null
}

$CorruptFiles = Get-ChildItem -Path $SourcePath -Filter "*.xmp" -Recurse -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^(203[8-9]|20[4-9]\d)' }

Write-Host "Found $($CorruptFiles.Count) corrupted sidecar files." -ForegroundColor Yellow

foreach ($File in $CorruptFiles) {
    Write-Host "Moving: $($File.Name) -> $QuarantinePath" -ForegroundColor Gray
    Move-Item -Path $File.FullName -Destination $QuarantinePath -Force
}