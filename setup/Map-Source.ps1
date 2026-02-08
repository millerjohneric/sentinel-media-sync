# ==============================================================================
# Sentinel Unified Network Mapper [S: Drive]
# ==============================================================================

$DriveLetter = 'S:'
$ShareName = 'Source'
$ComputerName = $env:COMPUTERNAME

# Determine if we are on GEEK or a remote device
if ($ComputerName -eq 'GEEK') {
    $NetworkPath = "C:\Source"
    Write-Host "Local host detected. Mapping S: to local Source folder." -ForegroundColor Cyan
} else {
    $NetworkPath = "\\GEEK\Source"
    Write-Host "Remote device detected. Mapping S: to network share." -ForegroundColor Cyan
}

# 1. Clean up existing S: drive if it exists
if (Get-PSDrive -Name ($DriveLetter.TrimEnd(':')) -ErrorAction SilentlyContinue) {
    Subst $DriveLetter /D | Out-Null
    net use $DriveLetter /delete /y 2>$null
    Write-Host "Resetting $DriveLetter mapping..." -ForegroundColor Gray
}

# 2. Apply Mapping
try {
    if ($ComputerName -eq 'GEEK') {
        # Use subst for local drive mapping (faster/more reliable for local host)
        subst $DriveLetter $NetworkPath
    } else {
        # Use net use for remote network mapping
        net use $DriveLetter $NetworkPath /persistent:yes
    }
    Write-Host "SUCCESS: $DriveLetter is now mapped to $NetworkPath" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not map drive." -ForegroundColor Red
}
