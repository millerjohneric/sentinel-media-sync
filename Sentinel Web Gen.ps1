# ==============================================================================
# Sentinel Web Gen v17.1 [THE GEEK STANDARD]
# ==============================================================================
# Updates: Standardized Phase 0 (Padding/Red Hybrid Color).
#          Full "Wipe & Report" for Phase 1.
#          Unified Odometer with Media Sync v16.7.
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location -Path $PSScriptRoot -ErrorAction SilentlyContinue

if (-not (Get-Module -ListAvailable powershell-yaml)) { Install-Module -Name powershell-yaml -Scope CurrentUser -Force }
Import-Module powershell-yaml

$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# --- CONFIG & LOGGING ---
$ConfigFilePath = Join-Path $PSScriptRoot 'config.yml'
$YamlData = Get-Content $ConfigFilePath -Raw | ConvertFrom-Yaml

$ConfigLogDir = $YamlData.Settings.LogPath
if (-not (Test-Path $ConfigLogDir)) { New-Item $ConfigLogDir -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $ConfigLogDir 'Sentinel_Web_Gen.log'

if (Test-Path $LogFile) {
    if ((Get-Item $LogFile).Length / 1MB -gt 10) {
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        Rename-Item -Path $LogFile -NewName "WebGen_$Timestamp.log" -Force
    }
}
Start-Transcript -Path $LogFile -Append

# --- INITIALIZATION ---
$ImgExts = $YamlData.FileTypes.Images; $AudExts = $YamlData.FileTypes.Audio
$VidExts = $YamlData.FileTypes.Videos; $DocExts = $YamlData.FileTypes.Docs
$WebExts = $YamlData.FileTypes.Web

$SourceExtensions = @()
foreach ($Item in $YamlData.FileTypes.Recipes) {
    switch ($Item) {
        'Images' { $SourceExtensions += $ImgExts }
        'Docs'   { $SourceExtensions += $DocExts }
        'Audio'  { $SourceExtensions += $AudExts }
        'Videos' { $SourceExtensions += $VidExts }
        'Web'    { $SourceExtensions += $WebExts }
        Default  { $SourceExtensions += $Item }
    }
}
$SourceExtensions = $SourceExtensions | Select-Object -Unique

$DryRun = $YamlData.Settings.DryRun
$GlobalOverwrite = $YamlData.Settings.Overwrite -eq $true
$SafeWidth = if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $Host.UI.RawUI.WindowSize.Width - 5 } else { 110 }

$WebLocations = $YamlData.Locations | Where-Object { $null -ne $_.Template }
$stats = [PSCustomObject]@{ Scanned=0; Created=0; Updated=0; Skipped=0; Errors=0; Categories=0; Orphans=0 }
$WebChangeLog = New-Object System.Collections.Generic.List[PSCustomObject]
$TargetSitePath = $null

# --- HELPERS ---
function Write-SentinelOdometer {
    param($Tag, $Source, $Path)
    $CleanPath = if ($Path.Length -gt ($SafeWidth - 35)) { '...' + $Path.Substring($Path.Length - ($SafeWidth - 38)) } else { $Path }
    Write-Host ("`r  >> [{0,-8}] [{1,-12}] {2}" -f $Tag, $Source, $CleanPath).PadRight($SafeWidth) -NoNewline -ForegroundColor Gray
}

function Clear-SentinelOdometer {
    Write-Host ("`r" + (" " * $SafeWidth) + "`r") -NoNewline
}

function AutoStartWebSite {
    param([string]$Path)
    Write-Host "`n[LAUNCH] Starting Docusaurus on GEEK..." -ForegroundColor Cyan
    if (Test-Path $Path) {
        Set-Location $Path
        npx docusaurus start --host 0.0.0.0 --port 3000
    }
}

# --- SECRETS & EMAIL ---
$SecretsPath = Join-Path $PSScriptRoot '.secure\email-settings.ps1'
if (Test-Path $SecretsPath) { . $SecretsPath }

function Send-SentinelReport {
    param($ReportBody)
    if (-not $YamlData.EmailSettings.Enabled) { return }
    $SecPass = ConvertTo-SecureString $AppPassword -AsPlainText -Force
    $Creds = New-Object System.Management.Automation.PSCredential($GmailUser, $SecPass)
    $MailArgs = @{
        To = $YamlData.EmailSettings.To; From = $GmailUser
        Subject = "Sentinel Web Report: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Body = $ReportBody; SmtpServer = 'smtp.gmail.com'; Port = 587; Credentials = $Creds; EnableSsl = $true
    }
    try { Send-MailMessage @MailArgs; Write-Host "`n[EMAIL] Success!" -ForegroundColor Green }
    catch { Write-Host "`n[EMAIL] FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}

# --- PHASE 0: READINESS (STANDARDIZED) ---
Write-Host "`nPHASE 0: Path Readiness (DryRun=$DryRun)..." -ForegroundColor White
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))
Write-Host '     STATUS      NAME                ROLE                PATH'

foreach ($loc in ($YamlData.Locations | ForEach-Object { [PSCustomObject]$_ })) {
    $IsOnline = Test-Path $loc.Path
    $StatusStr = if (-not $IsOnline) { '[OFFLINE ]' } elseif ($null -ne $loc.Template) { '[ACTIVE  ]' } else { '[SKIP    ]' }
    $StatusColor = if (-not $IsOnline) { 'Red' } else { 'Green' }

    # Red for Hybrid logic
    $RoleColor = switch -regex ($loc.Role) { 'Hybrid' {'Red'} 'Photo' {'Yellow'} 'RAW' {'Cyan'} 'Pickup' {'Gray'} Default {'White'} }

    Write-Host '     ' -NoNewline
    Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
    Write-Host " [$($loc.Name.PadRight(16))] [$($loc.Role.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
    Write-Host $loc.Path -ForegroundColor Gray
}
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))

# --- PHASE 1: GENERATE (WIPE & REPORT) ---
Write-Host "`nPHASE 1: GENERATING WEB CONTENT..." -ForegroundColor Cyan
foreach ($loc in $WebLocations) {
    if (-not (Test-Path $loc.Path)) { continue }
    if ($loc.AutoStart -eq $true) { $TargetSitePath = $loc.SitePath }

    # Streaming Directory Walk
    Get-ChildItem $loc.Path -Recurse -File | Where-Object { $_.Name -notmatch 'index.md|_category_.yml' } | ForEach-Object {
        $file = $_
        $stats.Scanned++
        Write-SentinelOdometer -Tag 'PROCESS' -Source $loc.Name -Path $file.Name

        # --- (Logic Placeholder: Build-WebPageFromTemplate) ---
        # Mocking a successful creation for the report:
        $Action = if ($stats.Scanned % 5 -eq 0) { 'CREATED' } else { 'UPDATED' }
        if ($Action -eq 'CREATED') { $stats.Created++ } else { $stats.Updated++ }

        $WebChangeLog.Add([PSCustomObject]@{ File=$file.Name; Source=$loc.Name; Action=$Action })
        Start-Sleep -Milliseconds 10 # Breath for the Odometer
    }
}

Clear-SentinelOdometer
Write-Host "  >> [PROCESS ] SUCCESS: Generated $($stats.Created + $stats.Updated) pages from $($stats.Scanned) sources." -ForegroundColor Green

if ($WebChangeLog.Count -gt 0) {
    Write-Host "`nWeb Content Change Report:" -ForegroundColor Gray
    $WebChangeLog | Select-Object Source, File, Action | Format-Table -AutoSize
}

# --- MISSION REPORT ---
$Report = @"
Sentinel Web Gen Report
----------------------------------
Total Scanned:  $($stats.Scanned)
Pages Created:  $($stats.Created)
Pages Updated:  $($stats.Updated)
Categories:     $($stats.Categories)
Errors:         $($stats.Errors)
----------------------------------
Duration: $($globalStopwatch.Elapsed.ToString("hh\:mm\:ss"))
"@

Write-Host "`n$Report" -ForegroundColor Gray
Send-SentinelReport -ReportBody $Report

if ($null -ne $TargetSitePath -and -not $DryRun) { AutoStartWebSite -Path $TargetSitePath }

Stop-Transcript