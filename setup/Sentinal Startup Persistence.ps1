$StartupFolder = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\Startup')
$LauncherPath = Join-Path $StartupFolder 'Start_Source_Services.bat'

$LauncherContent = @"
@echo off
:: Map the S: Drive locally
subst S: "C:\Source"

:: Launch the Sentinel Web Portal
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Set-Location 'C:\Source\GEEK\Sentinel'; .\Sentinel Web Gen.ps1"
"@

$LauncherContent | Set-Content -Path $LauncherPath
Write-Host "SUCCESS: Startup services linked to your Windows Login." -ForegroundColor Green