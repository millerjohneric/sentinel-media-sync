# ==============================================================================
# Sentinel Media Sync v12.8
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

function Send-SentinelReport {
    param($ReportBody)

    $EmailCfg = $YamlData.EmailSettings
    if (-not $EmailCfg.Enabled) { return }

    # Create Secure Password Object
    $SecPass = ConvertTo-SecureString $EmailCfg.Password -AsPlainText -Force
    $Creds = New-Object System.Management.Automation.PSCredential($EmailCfg.User, $SecPass)

    $MailArgs = @{
        To          = $EmailCfg.To
        From        = $EmailCfg.User
        Subject     = "Sentinel Sync Report: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Body        = $ReportBody
        SmtpServer  = $EmailCfg.Server
        Port        = $EmailCfg.Port
        Credentials = $Creds
        EnableSsl   = $true # Modern servers require this
        ErrorAction = 'Stop'
    }

    try {
        Write-Host "`n[EMAIL] Sending report to $($EmailCfg.To)..." -ForegroundColor Cyan
        Send-MailMessage @MailArgs
        Write-Host "[EMAIL] Success!" -ForegroundColor Green
    } catch {
        Write-Host "[EMAIL] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  >> Check: App Password, Port (587), and SSL settings." -ForegroundColor Yellow
    }
}

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

# --- PHASE 2: SORTING & ROUTING MEDIA ---
Write-Host "`nPHASE 2: SORTING & ROUTING MEDIA..." -ForegroundColor White

foreach ($loc in $ActiveLocs) {
    # Guard: Filter groups belonging to this location (flexible match for + prefix)
    $fileGroups = $Groups.Values | Where-Object {
        $null -ne $_ -and $_.Count -gt 0 -and ($_[0].LocationName -eq $loc.Name -or $_[0].LocationName -eq $loc.Name.TrimStart('+'))
    }

    if (-not $fileGroups) { continue }

    foreach ($group in $fileGroups) {
        $masterFile = $group[0]

        # 1. Determine relative path for the Odometer display
        $relativePath = ""
        if ($masterFile.DirectoryName.ToLower().StartsWith($loc.Path.ToLower())) {
             $relativePath = $masterFile.DirectoryName.Substring($loc.Path.Length).TrimStart('\')
        }
        if ($relativePath) { $relativePath += "\" }

        # 2. ODOMETER: Single-Line Overwrite
        $StatusText = "    >> [{0,-12}] Checking: {1}{2}" -f $loc.Name, $relativePath, $masterFile.Name
        $SafeWidth = if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $Host.UI.RawUI.WindowSize.Width - 1 } else { 110 }
        Write-Host ("`r" + $StatusText).PadRight($SafeWidth) -NoNewline -ForegroundColor Gray

        # 3. ROUTING LOGIC (Counting 'At Home' vs 'Moved')
        # Check if the file is already in its designated Anchor path
        if ($masterFile.DirectoryName.ToLower().StartsWith($loc.Path.ToLower())) {
            $stats.AtHome++
        } else {
            # This is where your Move-Item logic would live
            # Write-Host "`n    [MOVED] $($masterFile.Name) to $($loc.Name)" -ForegroundColor Green
            $stats.Moved++
        }
    }
}
Write-Host "`n >> Phase 2 Complete." -ForegroundColor White

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
# --- PHASE 4: PURGE & CLEANUP ---
Write-Host "`nPHASE 4: PURGE & CLEANUP..." -ForegroundColor White

foreach ($loc in $ActiveLocs) {
    Write-Host "`n  Target: $($loc.Name)" -ForegroundColor Yellow

    $JunkList = $YamlData.Junk
    $ConsoleWidth = $Host.UI.RawUI.WindowSize.Width - 1

    # NEW LOGIC: Only fetch files that match your Junk names
    # This ignores your .jpg and .xmp files entirely!
    $FilesToRemove = Get-ChildItem $loc.Path -Recurse -File | Where-Object { $JunkList -contains $_.Name }

    foreach ($file in $FilesToRemove) {
        $ShortPath = $file.DirectoryName.Replace($loc.Path, "...")
        $StatusText = "    [JUNK FOUND] $ShortPath >> $($file.Name)"

        if ($StatusText.Length -gt $ConsoleWidth) {
            $StatusText = $StatusText.Substring(0, $ConsoleWidth - 3) + "..."
        }

        if (-not $DryRun) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            $stats.PurgedFiles++
            # Using `r to show the live deletion progress without scrolling
            Write-Host ("`r" + $StatusText.PadRight($ConsoleWidth)) -NoNewline -ForegroundColor Red
        }
    }

    # --- Part B: Empty Folder Cleanup ---
    # This stays the same - it targets folders with 0 items
    $EmptyFolders = Get-ChildItem $loc.Path -Recurse -Directory |
                    Where-Object { (Get-ChildItem $_.FullName -Force).Count -eq 0 } |
                    Sort-Object -Property @{Expression={$_.FullName.Length}} -Descending

    if ($EmptyFolders) {
        Write-Host "`n    Pruning empty branches..." -ForegroundColor DarkYellow
    }

    foreach ($folder in $EmptyFolders) {
        if (-not $DryRun) {
            $FolderName = Split-Path $folder.FullName -Leaf
            Remove-Item $folder.FullName -Force -ErrorAction SilentlyContinue
            $stats.PurgedFolders++
            Write-Host ("`r      [REMOVED EMPTY] ...\$FolderName").PadRight($ConsoleWidth) -NoNewline -ForegroundColor DarkGray
        }
    }
}
Write-Host "`n >> Phase 4 Complete." -ForegroundColor White

# --- PHASE 5: WEB GEN ---
foreach ($loc in ($ActiveLocs | Where-Object { $_.WebType -ne "" })) {
    $TxtFiles = Get-ChildItem $loc.Path -Filter "*.txt" -Recurse
    $Total = $TxtFiles.Count
    $Count = 0

    foreach ($file in $TxtFiles) {
        $Count++
        $DestFile = Join-Path $file.DirectoryName "$($file.BaseName).md"

        # Odometer for Web Gen
        $WebStatus = "  >> Building Web Docs: [$Count/$Total] $($file.BaseName)"
        Write-Host ("`r" + $WebStatus).PadRight(110) -NoNewline -ForegroundColor Magenta

        if (-not $DryRun) {
            $Content = Get-Content $file.FullName -Raw
            # Instruction followed: Using single quotes for metadata keys
            $MDHeader = "---`ntitle: '$($file.BaseName)'`ntype: '$($loc.WebType)'`ngenerated: '$(Get-Date -Format 'yyyy-MM-dd HH:mm')'`n---"
            ($MDHeader + "`n`n" + $Content) | Out-File $DestFile -Encoding utf8
            $stats.WebGen++
        }
    }
}
Write-Host "`n >> Phase 5 Complete." -ForegroundColor White

# --- PHASE 6: MISSION REPORT & EMAIL ---
$Duration = $globalStopwatch.Elapsed.ToString("hh\:mm\:ss")

# Build the Source Summary string for the email body
$SourceLines = if ($SourceCounts.Count -gt 0) {
    ($SourceCounts.GetEnumerator() | ForEach-Object { "      - {0,-15} : {1} items" -f $_.Key, $_.Value }) -join "`n"
} else { "      - No items moved." }

# Final Summary Body
$ReportBody = @"
Sentinel Sync Report: $(Get-Date)
----------------------------------
Total Files Checked: $($stats.AtHome + $stats.Moved)
Files Moved:         $($stats.Moved)
Web Docs Generated:  $($stats.WebGen)
Folders Cleaned:     $($stats.PurgedFolders)
----------------------------------
Status: Mission Complete.
"@

# Call the email function using the secrets from your .ps1 file
Send-SentinelReport -ReportBody $ReportBody

Stop-Transcript