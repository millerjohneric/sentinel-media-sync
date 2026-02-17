# ==============================================================================
# PHASE 4: BUNDLING THE INSTALLER FOR ROENA
# ==============================================================================

$SetupDir = 'C:\Source\GEEK\Sentinel\setup'
if (!(Test-Path $SetupDir)) { New-Item -ItemType Directory -Path $SetupDir -Force }

# --- Create the Map-Source.ps1 script ---
$MapScript = @"
`$DriveLetter = 'S:'
`$ComputerName = `$env:COMPUTERNAME

if (Get-PSDrive -Name (`$DriveLetter.TrimEnd(':')) -ErrorAction SilentlyContinue) {
    subst `$DriveLetter /D | Out-Null
    net use `$DriveLetter /delete /y 2>`$null
}

if (`$ComputerName -eq 'GEEK') {
    subst `$DriveLetter 'C:\Source'
    Write-Host "Local S: Drive created for GEEK." -ForegroundColor Green
} else {
    net use `$DriveLetter '\\GEEK\Source' /persistent:yes
    Write-Host "Network S: Drive mapped for `$ComputerName." -ForegroundColor Green
}
"@
$MapScript | Set-Content -Path (Join-Path $SetupDir 'Map-Source.ps1')  -Encoding utf8

# --- Create the Double-Click Launcher (.bat) ---
$Launcher = @"
@echo off
echo ======================================================
echo           CONNECTING TO THE SOURCE (S:)
echo ======================================================
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Map-Source.ps1"
echo.
echo If you see Green text above, the S: Drive is ready!
pause
"@
$Launcher | Set-Content -Path (Join-Path $SetupDir 'CLICK_TO_CONNECT.bat') -Encoding utf8