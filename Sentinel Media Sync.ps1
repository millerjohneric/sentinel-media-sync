# ==============================================================================
# Sentinel Media Sync v16.7 [THE GEEK FINAL]
# ==============================================================================
# Updates: Fixed Phase 3 variable initialization ($ProcessedLocs).
#          Added Archive-Only Junk Purge (Phase 4).
#          Full "Wipe & Report" across all four phases.
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
$LogFile = Join-Path $ConfigLogDir 'Sentinel_Media_Sync.log'

if (Test-Path $LogFile) {
    if ((Get-Item $LogFile).Length / 1MB -gt 10) {
        $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        Rename-Item -Path $LogFile -NewName "MediaSync_$Timestamp.log" -Force
    }
}
Start-Transcript -Path $LogFile -Append

# --- DATA CLASS ---
class SentinelLocation {
    [string]$Path; [string]$Name; [string]$Role; [bool]$Enabled; [bool]$PurgeOrphan; [int]$Depth
    SentinelLocation([hashtable]$config) {
        $this.Path = if ($config['Path']) { $config['Path'].Replace('/', '\').TrimEnd('\') } else { '' }
        $this.Name = $config['Name']; $this.Role = $config['Role']
        $this.Depth = if ($null -ne $config['MonitorDepth']) { $config['MonitorDepth'] } else { 1 }
        $this.Enabled = ($this.Depth -ge 0)
        $this.PurgeOrphan = if ($null -ne $config['PurgeOrphan']) { [bool]$config['PurgeOrphan'] } else { $false }
    }
}

$Locations = $YamlData.Locations | ForEach-Object { [SentinelLocation]::new($_) }
$ActiveLocs = $Locations | Where-Object { $_.Enabled }
$lookupTable = @{}; $stats = [PSCustomObject]@{ Scanned=0; Moved=0; AtHome=0; Purged=0; Errors=0 }
$DryRun = $YamlData.Settings.DryRun; $ExifTool = $YamlData.SystemSettings.ExifToolPath
$SafeWidth = if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $Host.UI.RawUI.WindowSize.Width - 5 } else { 110 }

# --- HELPERS ---
function Write-SentinelOdometer {
    param($Tag, $Source, $Path)
    $CleanPath = if ($Path.Length -gt ($SafeWidth - 35)) { '...' + $Path.Substring($Path.Length - ($SafeWidth - 38)) } else { $Path }
    Write-Host ("`r  >> [{0,-8}] [{1,-12}] {2}" -f $Tag, $Source, $CleanPath).PadRight($SafeWidth) -NoNewline -ForegroundColor Gray
}

function Clear-SentinelOdometer {
    Write-Host ("`r" + (" " * $SafeWidth) + "`r") -NoNewline
}

function Get-MediaDate {
    param($file)
    if ($file.Name -match '(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})') {
        try { return Get-Date -Year $Matches.year -Month $Matches.month -Day $Matches.day -Hour 0 -Minute 0 -Second 0 } catch {}
    }
    return $file.CreationTime
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
        Subject = "Sentinel Sync Report: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Body = $ReportBody; SmtpServer = 'smtp.gmail.com'; Port = 587; Credentials = $Creds; EnableSsl = $true
    }
    try { Send-MailMessage @MailArgs; Write-Host "`n[EMAIL] Success!" -ForegroundColor Green }
    catch { Write-Host "`n[EMAIL] FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}

# --- PHASE 0: MASTER PLAN ---
Write-Host "`nPHASE 0: Path Readiness (DryRun=$DryRun)..." -ForegroundColor White
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))
Write-Host '     STATUS      NAME                ROLE                PATH'

foreach ($loc in $Locations) {
    $IsOnline = Test-Path $loc.Path
    $StatusStr = if (-not $IsOnline) { '[OFFLINE ]' } elseif ($loc.Enabled) { '[ACTIVE  ]' } else { '[SINK    ]' }
    $StatusColor = if (-not $IsOnline) { 'Red' } else { 'Green' }
    $RoleColor = switch -regex ($loc.Role) { 'Hybrid' {'Red'} 'Photo' {'Yellow'} 'RAW' {'Cyan'} 'Video|Audio' {'Magenta'} 'Pickup' {'Gray'} Default {'White'} }
    Write-Host '     ' -NoNewline
    Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
    Write-Host " [$($loc.Name.PadRight(16))] [$($loc.Role.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
    Write-Host $loc.Path -ForegroundColor Gray
}
Write-Host ('   + ' + ('-' * ($SafeWidth - 5)))

# --- PHASE 1: MAPPING ---
Write-Host "`nPHASE 1: MAPPING MEDIA..." -ForegroundColor Cyan
$MediaExts = $YamlData.FileTypes.Images + $YamlData.FileTypes.RAWs + $YamlData.FileTypes.Videos
foreach ($loc in $ActiveLocs) {
    if (-not (Test-Path $loc.Path)) { continue }
    $allFiles = Get-ChildItem -Path $loc.Path -File -Recurse:($loc.Depth -gt 1) | Where-Object { $MediaExts -contains $_.Extension.ToLower() }
    foreach ($file in $allFiles) {
        Write-SentinelOdometer -Tag 'SCAN' -Source $loc.Name -Path $file.Name
        $fileKey = "$($file.Length)_$($file.Name)"
        if (-not $lookupTable.ContainsKey($fileKey)) { $lookupTable[$fileKey] = New-Object System.Collections.Generic.List[System.IO.FileInfo] }
        $lookupTable[$fileKey].Add($file); $stats.Scanned++
    }
}
Clear-SentinelOdometer
Write-Host "  >> [SCAN    ] SUCCESS: $($stats.Scanned) items indexed." -ForegroundColor Green

# --- PHASE 2: ROUTING ---
Write-Host "`nPHASE 2: ROUTING MEDIA..." -ForegroundColor White
$MoveLog = New-Object System.Collections.Generic.List[PSCustomObject]
$LastDir = ''
foreach ($key in $lookupTable.Keys) {
    $group = $lookupTable[$key]; $master = $group[0]
    $origin = $ActiveLocs | Where-Object { $master.FullName.StartsWith($_.Path) } | Select-Object -First 1
    if ($null -eq $origin -or ($origin.Role -match 'Web|Hybrid' -and $origin.Role -ne 'InPlace_Archive')) { continue }

    if ($master.DirectoryName -ne $LastDir) {
        Write-SentinelOdometer -Tag 'ROUTING' -Source $origin.Name -Path $master.DirectoryName
        $LastDir = $master.DirectoryName
        Start-Sleep -Milliseconds 10
    }

    $mDate = Get-MediaDate -file $master
    $datePath = Join-Path $mDate.ToString('yyyy') $mDate.ToString('MM MMMM')

    if ($origin.Role -eq 'InPlace_Archive') {
        $Rel = $master.FullName.Replace($origin.Path, '').TrimStart('\')
        $Parts = $Rel -split '\\'
        $targetRoot = if ($Parts.Count -ge 2) { Join-Path $origin.Path (Join-Path $Parts[0] $Parts[1]) } else { $master.DirectoryName }
        if ($master.DirectoryName -match '\\\d{4}\\\d{2}\s\w+$') { $stats.AtHome++; continue }
    } else {
        $RoleType = if ($YamlData.FileTypes.RAWs -contains $master.Extension.ToLower()) { 'RAW_Archive' } else { 'Photo_Archive' }
        $targetRoot = ($ActiveLocs | Where-Object { $_.Role -eq $RoleType } | Select-Object -First 1).Path
    }

    if ($targetRoot) {
        $finalPath = Join-Path $targetRoot $datePath
        Write-SentinelOdometer -Tag 'MOVE' -Source $origin.Name -Path "$($master.Directory.Name)\$($master.Name)"
        if (-not $DryRun) {
            if (-not (Test-Path $finalPath)) { New-Item $finalPath -ItemType Directory -Force | Out-Null }
            try {
                Move-Item $master.FullName $finalPath -Force -ErrorAction Stop
                $stats.Moved++; $MoveLog.Add([PSCustomObject]@{ File=$master.Name; Source=$origin.Name; Status='MOVED' })
            } catch { $stats.Errors++ }
        }
    }
}
Clear-SentinelOdometer
Write-Host "  >> [ROUTING ] SUCCESS: $($stats.Moved) items routed to Archive structure." -ForegroundColor Green
if ($MoveLog.Count -gt 0) { $MoveLog | Format-Table -AutoSize }

# --- PHASE 3: REUNITING SIDECARS (ARCHIVE ONLY) ---
Write-Host "`nPHASE 3: REUNITING SIDECARS..." -ForegroundColor Cyan
$SidecarLog = New-Object System.Collections.Generic.List[PSCustomObject]
$ProcessedLocs = New-Object System.Collections.Generic.List[string]

foreach ($loc in $ActiveLocs) {
    if ($loc.Role -notmatch 'Archive') { continue }
    if (-not (Test-Path $loc.Path)) { continue }
    $ProcessedLocs.Add($loc.Name)

    Get-ChildItem $loc.Path -Recurse -Directory | ForEach-Object {
        $CurrentDir = $_.FullName
        Write-SentinelOdometer -Tag 'REUNITE' -Source $loc.Name -Path $CurrentDir
        $Sidecars = Get-ChildItem $CurrentDir -File -Filter *.xmp
        foreach ($s in $Sidecars) {
            $Buddy = Get-ChildItem $loc.Path -Recurse -File | Where-Object { $_.BaseName -eq $s.BaseName -and $_.Extension -ne '.xmp' } | Select-Object -First 1
            if ($Buddy -and $s.DirectoryName -ne $Buddy.DirectoryName) {
                Write-SentinelOdometer -Tag 'REUNITE' -Source $loc.Name -Path "$($Buddy.Directory.Name)\$($s.Name)"
                if (-not $DryRun) {
                    try {
                        Move-Item $s.FullName $Buddy.DirectoryName -Force -ErrorAction Stop
                        $SidecarLog.Add([PSCustomObject]@{ File=$s.Name; Location=$loc.Name; Status='REUNITED' })
                    } catch { $stats.Errors++ }
                }
            }
        }
    }
}
Clear-SentinelOdometer
Write-Host "  >> [REUNITE ] SUCCESS: Scanned Archives: $($ProcessedLocs -join ', ')" -ForegroundColor Green
if ($SidecarLog.Count -gt 0) { $SidecarLog | Format-Table -AutoSize }

# --- PHASE 4: JUNK PURGE (ARCHIVE ONLY) ---
Write-Host "`nPHASE 4: JUNK PURGE..." -ForegroundColor Red
$PurgeLog = New-Object System.Collections.Generic.List[PSCustomObject]
$JunkExts = $YamlData.FileTypes.Junk

foreach ($loc in $ActiveLocs) {
    if ($loc.Role -notmatch 'Archive') { continue }
    if (-not (Test-Path $loc.Path)) { continue }

    Get-ChildItem $loc.Path -Recurse -File | ForEach-Object {
        $file = $_
        Write-SentinelOdometer -Tag 'JUNK' -Source $loc.Name -Path $file.FullName
        if ($JunkExts -contains $file.Extension.ToLower()) {
            $PurgeLog.Add([PSCustomObject]@{ File=$file.Name; Location=$loc.Name; Status='PURGED' })
            if (-not $DryRun) {
                try { Remove-Item $file.FullName -Force -ErrorAction Stop; $stats.Purged++ }
                catch { $stats.Errors++ }
            }
        }
    }
}
Clear-SentinelOdometer
Write-Host "  >> [JUNK    ] SUCCESS: $($stats.Purged) junk files removed from Archives." -ForegroundColor Green
if ($PurgeLog.Count -gt 0) { $PurgeLog | Format-Table -AutoSize }

# --- MISSION REPORT ---
$Report = @"
Sentinel Sync Mission Report
----------------------------------
Total Scanned:  $($stats.Scanned)
Items Moved:    $($stats.Moved)
Already Home:   $($stats.AtHome)
Purged Files:   $($stats.Purged)
Errors:         $($stats.Errors)
----------------------------------
Duration: $($globalStopwatch.Elapsed.ToString('hh\:mm\:ss'))
"@
Write-Host "`n$Report" -ForegroundColor Gray
Send-SentinelReport -ReportBody $Report
Stop-Transcript