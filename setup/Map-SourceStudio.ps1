# ==============================================================================
# Sentinel Unified Network Mapper [S: Drive]
# ==============================================================================

$DriveLetter = 'W:'
$ShareName = 'Source_Studio'
$ComputerName = $env:COMPUTERNAME

# Determine if we are on GEEK or a remote device
if ($ComputerName -eq 'GEEK') {
    $NetworkPath = "C:\Source_Studio"
    Write-Host "Local host detected. Mapping W: to local Source_Studio folder." -ForegroundColor Cyan
} else {
    $NetworkPath = "\\GEEK\Source_Studio"
    Write-Host "Remote device detected. Mapping W: to network share." -ForegroundColor Cyan
}

# 1. Clean up existing W: drive if it exists
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
