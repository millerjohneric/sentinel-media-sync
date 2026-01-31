# ==============================================================================
# Sentinel Media Sync v11.4
# ==============================================================================
$DryRun = $false
$LineWidth = 115
$PhaseColor = if ($DryRun) { 'Green' } else { 'Red' }
# ==============================================================================
# Force the console to use UTF-8 encoding for special characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Set-Location -Path $PSScriptRoot -ErrorAction SilentlyContinue
if (-not (Get-Module -ListAvailable powershell-yaml)) { Install-Module -Name powershell-yaml -Scope CurrentUser -Force }
Import-Module powershell-yaml

# --- LOG ROTATION ---
$LogPath = Join-Path $PSScriptRoot "Sentinel_Session.log"
if (Test-Path $LogPath) {
    if (((Get-Item $LogPath).Length / 1MB) -gt 10) {
        $TS = Get-Date -Format "yyyyMMdd_HHmm"
        Rename-Item -Path $LogPath -NewName "Sentinel_Session_$TS.log"
    }
}
Start-Transcript -Path $LogPath -Append
# --- INITIALIZATION ---
$YamlData = Get-Content (Join-Path $PSScriptRoot 'config.yml') -Raw | ConvertFrom-Yaml
$ExifTool = $YamlData.SystemSettings.ExifToolPath
$ForceExif = [bool]$YamlData.SystemSettings.ExifRefresh
$MediaExts = $YamlData.FileTypes.Images + $YamlData.FileTypes.Raws + $YamlData.FileTypes.Videos + $YamlData.FileTypes.Audio
$SidecarExts = $YamlData.FileTypes.Sidecar
$allExts = $MediaExts + $SidecarExts
$OrphanPath = $YamlData.OrphanReviewPath

# DYNAMIC EXCLUSIONS: Use $YamlData (not $Config) and escape for safety
if ($YamlData.GlobalExclusions) {
    # Escaping ensures '.webaxs' is treated as literal text, not regex code
    $EscapedExclusions = $YamlData.GlobalExclusions | ForEach-Object { [regex]::Escape($_) }
    $ExclusionPattern = ($EscapedExclusions -join '|')
} else {
    $ExclusionPattern = '$^' # Matches nothing if the list is empty
}

# --- DATA CLASS V11 ---
class SentinelLocation {
    [string]$Path
    [string]$Name
    [bool]$ChronoSort
    [bool]$IsAnchor
    [bool]$Enabled
    [string]$WebType
    [bool]$WebUpdate
    [string]$RootType
    [string]$Scope
    [string]$TargetAnchor
    [bool]$RootOnly   # Added for the + Shield logic
    [bool]$Recursive  # Added to fix the blank Phase 1 scan issue

    SentinelLocation([hashtable]$config) {
        # Using your preferred single-quote key lookup for consistency
        $this.Path         = if ($config['Path']) { $config['Path'].Replace('/', '\').TrimEnd('\') } else { "" }
        $this.Name         = $config['Name']
        $this.ChronoSort   = [bool]$config['ChronoSort']
        $this.IsAnchor     = [bool]$config['Anchor']
        $this.Enabled      = if ($null -eq $config['Monitor']) { $true } else { [bool]$config['Monitor'] }
        $this.WebType      = [string]$config['WebType']
        $this.WebUpdate    = [bool]$config['WebUpdate']
        $this.RootType     = [string]$config['ROOTTYPE']
        $this.Scope        = [string]$config['Scope']

        # CRITICAL: This links Source -> Anchor
        $this.TargetAnchor = [string]$config['import_to']

        $this.RootOnly     = if ($null -eq $config['import_from_root_only']) { $false } else { [bool]$config['import_from_root_only'] }
        $this.Recursive    = if ($null -eq $config['Recursive']) { $false } else { [bool]$config['Recursive'] }
    }
}
$Locations = $YamlData.Locations | ForEach-Object { [SentinelLocation]::new($_) }
$ActiveLocs = $Locations | Where-Object { $_.Enabled }

$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$stats = [PSCustomObject]@{ Scanned=0; Moved=0; Error=0; WebGen=0; AtHome=0; PurgedFiles=0; PurgedFolders=0 }
$SourceCounts = @{}

# --- SECRETS & EMAIL CONFIG ---
$SecureDir = Join-Path $PSScriptRoot ".secure"
$SecretsPath = Join-Path $SecureDir "email-settings.ps1"

if (-not (Test-Path $SecureDir)) {
    New-Item -Path $SecureDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $SecretsPath)) {
    $Template = @"
# Sentinel Secure Email Credentials
`$GmailUser  = 'your-email@gmail.com'
`$AppPassword = 'your-google-app-password'
"@
    Set-Content -Path $SecretsPath -Value $Template
    Write-Host "`n[NOTICE] Created .secure\email-settings.ps1 template." -ForegroundColor Yellow
    Write-Host "Please edit this file with your credentials before running again." -ForegroundColor Red
    Pause
    exit
} else {
    . $SecretsPath
}

# Initialize Credentials
$Cred = if ($AppPassword) {
    New-Object System.Management.Automation.PSCredential ($GmailUser, (ConvertTo-SecureString $AppPassword -AsPlainText -Force))
}

# --- HELPER FUNCTIONS ---
function Get-MediaDate {
    param($file)
    if ($ForceExif -and (Test-Path $ExifTool)) {
        $tags = "-DateTimeOriginal", "-CreateDate", "-MediaCreateDate", "-DateCreated", "-GPSDateTime"
        foreach ($tag in $tags) {
            $val = & $ExifTool -s3 $tag $file.FullName 2>$null
            if ($val -match '^\d{4}:\d{2}:\d{2}') {
                try { return [DateTime]::ParseExact($val.Trim().Substring(0,19), "yyyy:MM:dd HH:mm:ss", $null) } catch {}
            }
        }
    }
    if ($file.Name -match '(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})') {
        try { return Get-Date -Year $Matches.year -Month $Matches.month -Day $Matches.day -Hour 0 -Minute 0 -Second 0 } catch {}
    }
    return $file.CreationTime
}

# --- PHASE 0: READINESS (V11 ENHANCED) ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8 # Fixes the â€¢ issue

Write-Host "`nPHASE 0: Path Readiness (DryRun=$DryRun)..." -ForegroundColor $PhaseColor
$ImageExts = $YamlData.FileTypes.Images + $YamlData.FileTypes.Raws
$VideoExts = $YamlData.FileTypes.Videos
$AudioExts = $YamlData.FileTypes.Audio
$MediaExts = $ImageExts + $VideoExts + $AudioExts

# --- COLOR LEGEND ---
Write-Host "  LEGEND: " -NoNewline -ForegroundColor Gray
Write-Host "YELLOW" -NoNewline -ForegroundColor Yellow; Write-Host "=Archive  " -NoNewline -ForegroundColor Gray
Write-Host "CYAN" -NoNewline -ForegroundColor Cyan; Write-Host "=Source  " -NoNewline -ForegroundColor Gray
Write-Host "MAGENTA" -NoNewline -ForegroundColor Magenta; Write-Host "=Web  " -NoNewline -ForegroundColor Gray
Write-Host "+" -NoNewline -ForegroundColor White; Write-Host "=RootOnly Shield" -ForegroundColor Gray
Write-Host "  FLAGS:  [R]=Recursive  [1]=Root Only  [W]=Web Docs" -ForegroundColor Gray
Write-Host "  " + ("-" * ($LineWidth - 4)) -ForegroundColor Gray

Write-Host "  STATUS      NAME            TYPE      FLAGS    PATH" -ForegroundColor Gray
Write-Host "  ----------  --------------  --------  -------  ----------------" -ForegroundColor Gray

foreach ($loc in $Locations) {
    $exists = Test-Path $loc.Path

    $st = if (-not $loc.Enabled) { "SINK" } elseif ($exists) { "ACTIVE" } else { "OFFLINE" }
    $stColor = if ($st -eq "ACTIVE") { "Green" } elseif ($st -eq "SINK") { "DarkGray" } else { "Red" }

    $typeLabel = if ($loc.IsAnchor) { "ANCHOR" } else { "SOURCE" }
    $nameColor = if ($loc.WebType) { "Magenta" }
                 elseif ($loc.IsAnchor) { "Yellow" }
                 else { "Cyan" }

    $fRec  = if ($loc.Recursive) { "R" } else { "-" }
    $fRoot = if ($loc.RootOnly) { "1" } else { "-" }
    $fWeb  = if ($loc.WebType) { "W" } else { "-" }
    $flags = "[$fRec$fRoot$fWeb]"

    Write-Host "  [" -NoNewline -ForegroundColor Gray
    Write-Host ("{0,-8}" -f $st) -ForegroundColor $stColor -NoNewline
    Write-Host "] [" -NoNewline -ForegroundColor Gray

    # Prefix "+" for Root-Only protected locations (Encoding Safe)
    $displayName = if ($loc.RootOnly) { "+$($loc.Name)" } else { $loc.Name }
    Write-Host ("{0,-12}" -f $displayName) -ForegroundColor $nameColor -NoNewline

    Write-Host "] [" -NoNewline -ForegroundColor Gray
    Write-Host ("{0,-6}" -f $typeLabel) -ForegroundColor White -NoNewline
    Write-Host "] " -NoNewline -ForegroundColor Gray
    Write-Host ("{0,-7}" -f $flags) -ForegroundColor Gray -NoNewline
    Write-Host $loc.Path -ForegroundColor $stColor
}
$lookupTable = @{} # Initialize the master index
# --- PHASE 1: MAPPING FILESYSTEM (V12) ---
# --- PHASE 1: MAPPING FILESYSTEM (V12) ---
foreach ($loc in $ActiveLocs) {
    Write-Host "  Location: $($loc.Name) (Recursive=$($loc.Recursive))" -ForegroundColor Gray

    # Define parameters dynamically based on Class property
    $gciArgs = @{
        Path    = $loc.Path
        File    = $true
        Recurse = $loc.Recursive  # This uses the [bool] from your class
        ErrorAction = 'SilentlyContinue'
    }

    $allFiles = Get-ChildItem @gciArgs
    $count = 0

    foreach ($file in $allFiles) {
        # Filter for Media Only
        if ($MediaExts -contains $file.Extension) {
            # Use -Force to stop the "MemberAlreadyExists" error
            $file | Add-Member -MemberType NoteProperty -Name "SourceName" -Value $loc.Name -Force

            $fileKey = "$($file.Length)_$($file.Name)"
            if (-not $lookupTable.ContainsKey($fileKey)) {
                $lookupTable[$fileKey] = New-Object System.Collections.Generic.List[System.IO.FileInfo]
            }
            $lookupTable[$fileKey].Add($file)
            $count++
        } elseif ($SidecarExts -contains $file.Extension) {
            if ($null -eq $Orphans) { $Orphans = New-Object System.Collections.Generic.List[System.IO.FileInfo] }
            $Orphans.Add($file)
        }
    }
    Write-Host "    >> Success: Indexed $count items." -ForegroundColor Green
}

# --- GROUPING SUMMARY ---
$groupCount = $lookupTable.Keys.Count
Write-Host "`nBUILDING FILE GROUPS..." -ForegroundColor $PhaseColor
Write-Host "    >> Success: Grouped into $groupCount unique file sets." -ForegroundColor Green

# --- PHASE 2: SORTING & ROUTING MEDIA (V12.0) ---
Write-Host "`nPHASE 2: SORTING & ROUTING MEDIA..." -ForegroundColor $PhaseColor

foreach ($key in $lookupTable.Keys) {
    $fileGroup = $lookupTable[$key]
    $masterFile = $fileGroup[0]
    $loc = $Locations | Where-Object { $_.Name -eq $masterFile.SourceName }
    # 1. SMART ANCHOR SELECTION
    # If the file is a Video, look for the 'Videos' Anchor.
    # If it's Audio, look for 'Audio', etc.
    $TargetType = if ($YamlData.FileTypes.Videos -contains $masterFile.Extension) { "Videos" }
                  elseif ($YamlData.FileTypes.Audio -contains $masterFile.Extension) { "Audio" }
                  else { "Photos" } # Default to Photos for Images/Raws

    # Find the actual Anchor object that matches this type
    $DestLoc = $Locations | Where-Object { $_.IsAnchor -and $_.Name -like "*$TargetType*" }
    # Inline Path Reporting
    $relativePath = $masterFile.DirectoryName.Replace($loc.Path, "").TrimStart('\')
    if ($relativePath) { $relativePath += "\" }

    Write-Host "  >> [" -NoNewline -ForegroundColor Gray
    Write-Host ("{0,-12}" -f $loc.Name) -ForegroundColor Cyan -NoNewline
    Write-Host "] Processing: " -NoNewline -ForegroundColor Gray
    Write-Host "$relativePath" -NoNewline -ForegroundColor Yellow
    Write-Host "$($masterFile.Name)" -ForegroundColor White

    # --- DETERMINE TARGET DIRECTORY ---
    $TargetDir = $null

    if ($loc.IsAnchor) {
        # 1. Archive Logic: Sort in place if ChronoSort is enabled, else stay put
        if ($loc.ChronoSort) {
            $BestDate = Get-MediaDate $masterFile
            $TargetDir = Join-Path $loc.Path ($BestDate.ToString("yyyy\\MM MMMM"))
        } else {
            $TargetDir = $masterFile.DirectoryName
        }
    } elseif ($DestLoc) {
        # 2. Source Logic: Move to the mapped Anchor using Date-Coding
        $BestDate = Get-MediaDate $masterFile
        $TargetDir = Join-Path $DestLoc.Path ($BestDate.ToString("yyyy\\MM MMMM"))
    } else {
        # 3. Fallback: If no destination is defined, stay where you are
        $TargetDir = $masterFile.DirectoryName
    }

    # Safety catch for null TargetDir (prevents TrimEnd crashes)
    if (-not $TargetDir) { $TargetDir = $masterFile.DirectoryName }

    # --- EXECUTE MOVE / VERIFICATION ---
    $itemCount = 1
    foreach ($item in $fileGroup) {
        $currentDirPath = if ($item.DirectoryName) { $item.DirectoryName.TrimEnd('\') } else { "" }
        $targetDirPath = $TargetDir.TrimEnd('\')

        if ($currentDirPath -eq $targetDirPath) {
            $stats.AtHome++
            # Back to real filenames for full transparency
            Write-Host "     [OK] $($item.Name)" -NoNewline -ForegroundColor DarkGray
            Write-Host " already in: $($item.DirectoryName)" -ForegroundColor Gray
            continue
        }

        $logPrefix = if ($DryRun) { "[SIM]" } else { "[MOVE]" }
        Write-Host "     $logPrefix $($item.Name) -> $TargetDir" -ForegroundColor DarkGreen
        # --- THE TRANSPARENCY UPGRADE ---
        Write-Host "     $logPrefix From: $($item.FullName)" -ForegroundColor DarkYellow
        Write-Host "     $logPrefix   To: $(Join-Path $TargetDir $item.Name)" -ForegroundColor DarkGreen
        if (-not $DryRun) {
            if (-not (Test-Path $TargetDir)) {
                New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            }
            $destPath = Join-Path $TargetDir $item.Name
            Move-Item -LiteralPath $item.FullName -Destination $destPath -Force
        }

        $stats.Moved++
        $SourceCounts[$loc.Name]++
        $itemCount++
    }
}

# --- PHASE 2 SUMMARY ---
Write-Host "`n  ROUTING COMPLETE:" -ForegroundColor Gray
Write-Host "  ------------------------------------" -ForegroundColor Gray
Write-Host "  Verified 'At Home' : $($stats.AtHome)" -ForegroundColor Cyan
Write-Host "  Scheduled to Move : $($stats.Moved)" -ForegroundColor Yellow
Write-Host "  ------------------------------------`n" -ForegroundColor Gray

# --- PHASE 3: CLEANING UP ORPHANED SIDECARS (V1.2) ---
if ($Orphans.Count -gt 0) {
    Write-Host "`nPHASE 3: CLEANING UP ORPHANED SIDECARS..." -ForegroundColor $PhaseColor

    foreach ($sidecar in $Orphans) {
        # SKIP LOGIC: Don't move web-structure files
        if ($sidecar.Name -eq "_category_.yml" -or $sidecar.Extension -eq ".md") {
            Write-Host "  >> Skipping System File: $($sidecar.Name)" -ForegroundColor DarkGray
            continue
        }

        Write-Host "  >> Orphan Found: $($sidecar.Name)" -ForegroundColor Magenta

        # Define destination: Create an 'Orphans' folder inside the current directory
        $OrphanPath = Join-Path $sidecar.DirectoryName "Orphans"

        if ($DryRun) {
            Write-Host "     [SIM] -> $OrphanPath" -ForegroundColor DarkGreen
        } else {
            if (-not (Test-Path -Path $OrphanPath)) {
                New-Item -Path $OrphanPath -ItemType Directory -Force | Out-Null
            }
            $destFile = Join-Path $OrphanPath $sidecar.Name
            Move-Item -LiteralPath $sidecar.FullName -Destination $destFile -Force
            Write-Host "     [MOVED] -> $OrphanPath" -ForegroundColor DarkGreen
        }
    }
}

# --- PHASE 4: PURGE & CLEANUP (V12.3 - High Performance) ---
if (-not $DryRun) {
    Write-Host "`nPHASE 4: PURGE & CLEANUP..." -ForegroundColor $PhaseColor
    $Exclusions = $YamlData.GlobalExclusions # Check your YAML key name

    foreach ($loc in $ActiveLocs) {
        Write-Host "  Scrubbing: $($loc.Name)" -ForegroundColor Cyan

        # Use .NET EnumerateFiles for massive speed gains over Get-ChildItem
        try {
            $directory = [System.IO.Directory]::EnumerateFiles($loc.Path, "*", [System.IO.SearchOption]::AllDirectories)

            foreach ($filePath in $directory) {
                $fileName = [System.IO.Path]::GetFileName($filePath)

                # Live Heartbeat (Truncated for long names)
                $shortName = if ($fileName.Length -gt 40) { $fileName.Substring(0,37) + "..." } else { $fileName }
                Write-Host ("`r    >> Checking: $shortName").PadRight($LineWidth) -NoNewline -ForegroundColor Gray

                if ($Exclusions -contains $fileName) {
                    Write-Host "`r    [DELETE] $fileName" -ForegroundColor Yellow
                    Remove-Item -LiteralPath $filePath -Force
                    $stats.PurgedFiles++
                }
            }
        } catch {
            Write-Warning "      Could not access subfolders in $($loc.Name)"
        }

        # 2. REMOVE EMPTY FOLDERS (Still uses GCI but sorted for depth)
        $dirs = Get-ChildItem $loc.Path -Recurse -Directory | Sort-Object FullName -Descending
        foreach ($dir in $dirs) {
            if (-not (Get-ChildItem $dir.FullName -Force | Select-Object -First 1)) {
                Write-Host "`r    [REMOVED] Empty Dir: $($dir.Name)".PadRight($LineWidth) -ForegroundColor DarkGray
                Remove-Item -LiteralPath $dir.FullName -Force
                $stats.PurgedFolders++
            }
        }
    }
    Write-Host ("`r" + " " * $LineWidth) -NoNewline
    Write-Host "`r    >> Purge Complete: $($stats.PurgedFiles) files / $($stats.PurgedFolders) folders removed." -ForegroundColor Green
} else {
    Write-Host "`nPHASE 4: PURGE & CLEANUP (SKIPPED - DryRun)" -ForegroundColor DarkGray
}


# --- PHASE 5: WEB GEN (Transparency Update) ---
foreach ($loc in ($ActiveLocs | Where-Object { $_.WebType -ne "" })) {
    Write-Host "  Processing: $($loc.Name)" -ForegroundColor White
    Get-ChildItem $loc.Path -Filter "*.txt" -Recurse | ForEach-Object {
        $DestFile = Join-Path $_.DirectoryName "$($_.BaseName).md"

        if (Test-Path $DestFile) {
            Write-Host "    [UPDATE] $($_.BaseName).md" -ForegroundColor Gray
        } else {
            Write-Host "    [CREATE] $($_.BaseName).md" -ForegroundColor Magenta
        }

        if (-not $DryRun) {
            $Content = Get-Content $_.FullName -Raw
            $MDHeader = "---\ntitle: '$($_.BaseName)'\ntype: '$($loc.WebType)'\ngenerated: '$(Get-Date -Format 'yyyy-MM-dd HH:mm')'\n---\n"
            ($MDHeader + "`n`n" + $Content) | Out-File $DestFile -Encoding utf8
            $stats.WebGen++ # Now the email will show how many recipes were built!
        }
    }
}
# --- PHASE 6: MISSION REPORT & EMAIL ---
$Duration = $globalStopwatch.Elapsed.ToString("hh\:mm\:ss")

# Build the Source Summary string for the email body
$SourceLines = if ($SourceCounts.Count -gt 0) {
    ($SourceCounts.GetEnumerator() | ForEach-Object { "      - {0,-15} : {1} items" -f $_.Key, $_.Value }) -join "`n"
} else { "      - No items moved." }

$Report = @"
SENTINEL MISSION COMPLETE
------------------------------------
Date:     $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Mode:     $(if ($DryRun){'DRY RUN'}else{'LIVE'})
Runtime:  $Duration

STATISTICS:
- Moved:     $($stats.Moved)
- Verified:  $($stats.AtHome)
- WebGen:    $($stats.WebGen)
- Purged:    $($stats.PurgedFiles) Files / $($stats.PurgedFolders) Folders

SOURCE RECAP:
$SourceLines
------------------------------------
"@

# Output to console
Write-Host "`n$Report" -ForegroundColor Cyan

# Send the Email
if (-not $DryRun -and $Cred) {
    try {
        $MailArgs = @{
            To          = $YamlData.EmailSettings.EmailTo
            From        = $YamlData.EmailSettings.EmailFrom
            Subject     = "Sentinel Mission Report - $(Get-Date -Format 'yyyy-MM-dd')"
            Body        = $Report
            SmtpServer  = $YamlData.EmailSettings.SMTPServer
            Port        = $YamlData.EmailSettings.SMTPPort
            Credential  = $Cred
            UseSsl      = $true
            ErrorAction = 'Stop'
        }
        Send-MailMessage @MailArgs
        Write-Host ">> Email Report Sent Successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Email failed to send: $($_.Exception.Message)"
    }
}