# ==============================================================================
# PHASE 4: APPLY PROFESSIONAL BRANDING
# ==============================================================================

# 1. Load Configuration
$ConfigPath = Join-Path $PSScriptRoot '..\config2.0.yml'
if (!(Test-Path $ConfigPath)) { Write-Error "Config missing at $ConfigPath"; exit }

$ConfigContent = Get-Content $ConfigPath -Raw
$DriveLetter = ($ConfigContent | Select-String -Pattern "'Volume':\s+'([^']+)'").Matches.Groups[1].Value
$IconName = ($ConfigContent | Select-String -Pattern "'DriveIcon':\s+'([^']+)'").Matches.Groups[1].Value
$DriveName = ($ConfigContent | Select-String -Pattern "'Network':\s+'([^']+)'").Matches.Groups[1].Value
$PhysicalRoot = ($ConfigContent | Select-String -Pattern "'Data_Root':\s+'([^']+)'").Matches.Groups[1].Value

# 2. Determine Best Target (Mapped S: or Physical C:\Source)
$TargetDrive = "$($DriveLetter)\"
if (!(Test-Path $TargetDrive)) {
    Write-Host "Drive $TargetDrive not found. Falling back to physical path: $PhysicalRoot" -ForegroundColor Yellow
    $TargetDrive = $PhysicalRoot
}

if (!(Test-Path $TargetDrive)) {
    Write-Error "CRITICAL: Neither $DriveLetter nor $PhysicalRoot exist. Run 'Root of all Creation.ps1' first."
    exit
}

# 3. Apply Branding
$IconSource = Join-Path $PSScriptRoot $IconName
$IconDestination = Join-Path $TargetDrive $IconName
$AutorunPath = Join-Path $TargetDrive 'autorun.inf'

Write-Host "Branding target identified: $TargetDrive" -ForegroundColor Cyan

# Copy Icon
if (Test-Path $IconSource) {
    if ($IconSource -ne $IconDestination) {
        Copy-Item -Path $IconSource -Destination $IconDestination -Force
        attrib +h +s $IconDestination
        Write-Host "Successfully copied $IconName to $TargetDrive" -ForegroundColor Green
    }
}

# Create Autorun
$AutorunContent = @"
[Autorun]
Icon=$IconName
Label=$DriveName
"@

$AutorunContent | Set-Content -Path $AutorunPath -Encoding Ascii
attrib +h +s $AutorunPath

Write-Host "SUCCESS: The Source branding applied." -ForegroundColor Green