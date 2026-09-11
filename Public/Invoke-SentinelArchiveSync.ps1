function Global:Invoke-SentinelArchiveSync {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Locations,

        [Parameter(Mandatory = $true)]
        [hashtable]$FileTypes,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )
    # Read configuration format settings dynamically
    $ConfigPath = "C:\Source\GEEK\Sentinel\sentinel-media-sync\Sentinel-Config.yml"
    $ConfigFormat = "YYYY/MM Month" # Default fallback
    if (Test-Path -Path $ConfigPath) {
        $ConfigRaw = Get-Content -Path $ConfigPath -Raw
        if ($ConfigRaw -match 'DateFormat\s*:\s*[''"]?([^''"\r\n]+)[''"]?') {
            $ConfigFormat = $Matches[1].Trim()
        }
    }
    
    $DryRun   = $Settings.DryRun
    
    # Force lowercase and leading dots on all input extensions with safe array casting
    # ---------------------------------------------------------
    # 2. EXTENSION MAPPING & SANITIZATION
    # ---------------------------------------------------------
    $ImgExts  = @($FileTypes['Images']) | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }
    $RawExts  = @($FileTypes['RAWs'])   | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }
    $AudExts  = @($FileTypes['Audio'])  | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }
    $DocExts  = @($FileTypes['Docs'])   | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }
    $WebExts  = @($FileTypes['Web'])    | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }
    $SideExts = @($FileTypes['Sidecars'])| ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }
    
    $JunkList = @($FileTypes['Junk'])
    $Exclusions = @($FileTypes['Exclusions'])

    $VideoKeys = @('Videos', 'Video', 'Vid')
    $VideoRaw  = foreach ($k in $VideoKeys) { if ($FileTypes[$k]) { $FileTypes[$k] } }
    $VidExts   = @($VideoRaw) | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { if ($_) { $_.ToLower() } }

    # Fallback if video extensions are missing
    if (-not $VidExts -or $VidExts.Count -eq 0) {
        $VidExts = @('.mp4', '.mov', '.avi', '.mkv', '.m4v', '.wmv', '.flv', '.webm', '.mts', '.m2ts')
    }
    # Fallback default image extensions if YAML hashtable failed to load Images key
    if (-not $ImgExts -or $ImgExts.Count -eq 0) {
        $ImgExts = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.heic')
    }

    $SkipSidecars = $Settings.DisableSidecarReunion -eq $true -or $Settings.DisableSidecarReunion -eq 'true'
    $SkipJunk     = $Settings.DisableJunkPurge -eq $true -or $Settings.DisableJunkPurge -eq 'true'

    if ($SkipSidecars) {
        $AllMedia = $ImgExts + $RawExts + $VidExts + $AudExts
    } else {
        $AllMedia = $ImgExts + $RawExts + $VidExts + $AudExts + @('.xmp')
    }

    $PickupLocs   = $Locations | Where-Object { $_.Role -eq 'Pickup' }
    $TimelineLoc  = $Locations | Where-Object { $_.Role -eq 'timeline' } | Select-Object -First 1
    $RawLoc       = $Locations | Where-Object { $_.Role -eq 'RAW_Archive' } | Select-Object -First 1
    $VideoLoc     = $Locations | Where-Object { $_.Role -eq 'Video_Archive' } | Select-Object -First 1
    $AudioLoc     = $Locations | Where-Object { $_.Role -eq 'Audio_Archive' } | Select-Object -First 1
    $ArchiveLocs  = $Locations | Where-Object { $_.Role -match 'Archive|timeline|Hybrid' }

    $Stats = @{ Scanned = 0; Moved = 0; Reunited = 0; Purged = 0; Errors = 0 }

    Write-Host "`nARCHIVE SYNC: Routing Pickup Zones..." -ForegroundColor Cyan
    foreach ($Loc in $PickupLocs) {
        if (-not (Test-Path -Path $Loc.Path)) {
            Write-Host "  $($Global:Icons.Warning) OFFLINE: $($Loc.Name)" -ForegroundColor DarkGray
            continue
        }
        
        # Added -Force to capture hidden/system screenshot files from SnippingTool
        $Files = Get-ChildItem -Path $Loc.Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $AllMedia -contains $_.Extension.ToLower() }
            
        Write-Host "  -> Checking $($Loc.Name): Found $(($Files).Count) matched files in path: $($Loc.Path)" -ForegroundColor Yellow

        $Total = $Files.Count
        $Count = 0

        foreach ($File in $Files) {
            $Stats.Scanned++
            $Count++
            $Ext = $File.Extension.ToLower()

            if (Get-Command -Name Test-SentinelExclusion -ErrorAction SilentlyContinue) {
                if (Test-SentinelExclusion -FullPath $File.FullName) { continue }
            }

            # Helper function to extract EXIF Date Taken safely using Shell.Application
            function Get-ExifDateTaken {
                param ([Parameter(Mandatory = $true)] [string]$FilePath)
                try {
                    $Shell = New-Object -ComObject Shell.Application
                    $ParentDir = [System.IO.Path]::GetDirectoryName($FilePath)
                    $FileName = [System.IO.Path]::GetFileName($FilePath)
                    $Folder = $Shell.Namespace($ParentDir)
                    if ($Folder) {
                        $ShellFile = $Folder.ParseName($FileName)
                        if ($ShellFile) {
                            # Property index 12 is typically "Date taken"
                            $DateStr = $Folder.GetDetailsOf($ShellFile, 12)
                            if (-not [string]::IsNullOrWhiteSpace($DateStr)) {
                                # Clean up formatting characters (like directional marks) often returned by Shell
                                $CleanDateStr = $DateStr -replace '[^\d/:\s]', ''
                                [datetime]$ParsedExif = 0
                                if ([datetime]::TryParse($CleanDateStr, [ref]$ParsedExif)) {
                                    return $ParsedExif
                                }
                            }
                        }
                    }
                } catch { }
                return $null
            }

            # Date fallback resolution order: 
            # 1. Filename regex match
            # 2. EXIF / Metadata Date Taken (for images & videos)
            # 3. File Creation/LastWrite timestamp
            $FileDate = $null
            if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                try { 
                    $FileDate = Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 
                } catch { }
            }

            if (-not $FileDate) {
                $FileDate = Get-ExifDateTaken -FilePath $File.FullName
            }

            if (-not $FileDate) {
                $FileDate = $File.CreationTime
            }

            # Translate config format tokens into C#/.NET date patterns safely, preserving your exact folder layout style
            $YearPart  = $FileDate.ToString('yyyy')
            $MonthNum  = $FileDate.ToString('MM')
            $MonthName = $FileDate.ToString('MMMM')
            
            $SubPart    = "$YearPart-$MonthNum $MonthName"
            $DateFolder = Join-Path -Path $YearPart -ChildPath $SubPart

            # Robust Target Root mapping with fallback defaults
            $TargetRoot = $null
            if ($RawExts -contains $Ext) { 
                $TargetRoot = $RawLoc?.Path 
            }
            elseif ($VidExts -contains $Ext) { 
                $TargetRoot = $VideoLoc?.Path 
            }
            elseif ($AudExts -contains $Ext) { 
                $TargetRoot = $AudioLoc?.Path 
            }
            
            # Fallback for Images and Sidecars: Default to timeline path if Role search missed it
            if ([string]::IsNullOrWhiteSpace($TargetRoot) -and ($ImgExts -contains $Ext -or $Ext -eq '.xmp')) {
                $TargetRoot = if ($TimelineLoc?.Path) { $TimelineLoc.Path } else { "L:\Photo_Archive\timeline" }
            }

            if ([string]::IsNullOrWhiteSpace($TargetRoot)) { continue }

            $Destination = Join-Path -Path $TargetRoot -ChildPath $DateFolder

            if (Get-Command -Name Write-SentinelOdometer -ErrorAction SilentlyContinue) {
                Write-SentinelOdometer -Tag "ROUTE" -Source $Loc.Name -Path $File.Name -Destination $Destination -Current $Count -Total $Total
            } else {
                Write-Host "  -> [$Count/$Total] $($File.Name) => $Destination" -ForegroundColor Gray
            }

            if (-not $DryRun) {
                try {
                    if (-not (Test-Path -Path $Destination)) { 
                        New-Item -Path $Destination -ItemType Directory -Force | Out-Null 
                    }
                    
                    $TargetFile = Join-Path -Path $Destination -ChildPath $File.Name
                    
                    # If destination file already exists, generate a non-conflicting filename
                    if (Test-Path -Path $TargetFile) {
                        $BaseName  = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
                        $Extension = [System.IO.Path]::GetExtension($File.Name)
                        $Counter   = 1
                        
                        while (Test-Path -Path $TargetFile) {
                            $NewName    = "${BaseName}_${Counter}${Extension}"
                            $TargetFile = Join-Path -Path $Destination -ChildPath $NewName
                            $Counter++
                        }
                    }
                    
                    Move-Item -Path $File.FullName -Destination $TargetFile -Force -ErrorAction Stop
                    $Stats.Moved++
                    
                } catch {
                    $Stats.Errors++
                    Write-Host "`n  $($Global:Icons.Error) Failed to move '$($File.Name)': $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        Write-Host ""
    }

    # --- SIDECAR REUNION PHASE ---
    if (-not $SkipSidecars) {
        Write-Host "  $($Global:Icons.Arrow) Reuniting orphaned sidecars..." -ForegroundColor Gray
        
        foreach ($ArchiveLoc in $ArchiveLocs) {
            if (-not (Test-Path -Path $ArchiveLoc.Path)) { continue }

            Write-Host "    $($Global:Icons.Arrow) Scanning sidecars in: $($ArchiveLoc.Name)" -ForegroundColor DarkGray
            $Sidecars = Get-ChildItem -Path $ArchiveLoc.Path -Filter *.xmp -Recurse -Force -ErrorAction SilentlyContinue
            $TotalSidecars = $Sidecars.Count
            $CurrentSidecar = 0

            foreach ($S in $Sidecars) {
                $CurrentSidecar++
                if (Get-Command -Name Write-SentinelOdometer -ErrorAction SilentlyContinue) {
                    Write-SentinelOdometer -Tag "REUNITE" -Source $ArchiveLoc.Name -Path $S.Name -Destination "" -Current $CurrentSidecar -Total $TotalSidecars
                }

                try {
                    if (Get-Command -Name Get-SentinelBuddy -ErrorAction SilentlyContinue) {
                        $Buddy = Get-SentinelBuddy -Sidecar $S -SearchRoot $ArchiveLoc.Path -ErrorAction Stop
                        if ($Buddy -and $Buddy.NeedsReunion) {
                            if (-not $DryRun) {
                                Move-Item -Path $S.FullName -Destination $Buddy.Target -Force -ErrorAction Stop
                            }
                            $Stats.Reunited++
                        }
                    }
                }
                catch {
                    Write-Host ""
                    Write-Host "    $($Global:Icons.Error) Failed sidecar: $($S.Name)" -ForegroundColor Red
                    $Stats.Errors++
                }
            }
            Write-Host ""
        }
        Write-Host "    $($Global:Icons.Check) Sidecars: $($Stats.Reunited) reunited, $($Stats.Purged) orphans purged." -ForegroundColor Gray
    } else {
        Write-Host "  $($Global:Icons.Check) Sidecar reunion skipped per configuration." -ForegroundColor Gray
    }

    # --- UNSORTED MONTH FOLDER SORTING ---
    Write-Host "  $($Global:Icons.Arrow) Sorting unsorted files into month folders..." -ForegroundColor Gray
    $SortedCount = 0
    foreach ($Loc in $ArchiveLocs) {
        if (-not (Test-Path -Path $Loc.Path)) { continue }

        Get-ChildItem -Path $Loc.Path -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}$' } |
            ForEach-Object {
                $YearDir = $_.FullName
                $LooseFiles = Get-ChildItem -Path $YearDir -File -Force -ErrorAction SilentlyContinue

                foreach ($File in $LooseFiles) {
                    $Ext = $File.Extension.ToLower()
                    if ($AllMedia -notcontains $Ext) { continue }

                    $FileDate = $null
                    if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                        try { 
                            $FileDate = Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 
                        } catch { }
                    }

                    if (-not $FileDate) {
                        $FileDate = Get-ExifDateTaken -FilePath $File.FullName
                    }

                    if (-not $FileDate) {
                        $FileDate = $File.CreationTime
                    }

                    $YearPart  = $FileDate.ToString('yyyy')
                    $MonthNum  = $FileDate.ToString('MM')
                    $MonthName = $FileDate.ToString('MMMM')
                    $MonthFolder = Join-Path -Path $YearDir -ChildPath "$YearPart-$MonthNum $MonthName"
                    $SortedCount++

                    if (-not $DryRun) {
                        try {
                            if (-not (Test-Path -Path $MonthFolder)) { 
                                New-Item -Path $MonthFolder -ItemType Directory -Force | Out-Null 
                            }
                            
                            $TargetFile = Join-Path -Path $MonthFolder -ChildPath $File.Name
                            
                            # If destination file already exists, generate a non-conflicting filename
                            if (Test-Path -Path $TargetFile) {
                                $BaseName  = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
                                $Extension = [System.IO.Path]::GetExtension($File.Name)
                                $Counter   = 1
                                
                                while (Test-Path -Path $TargetFile) {
                                    $NewName    = "${BaseName}_${Counter}${Extension}"
                                    $TargetFile = Join-Path -Path $MonthFolder -ChildPath $NewName
                                    $Counter++
                                }
                            }
                            
                            Move-Item -Path $File.FullName -Destination $TargetFile -Force -ErrorAction Stop
                            $Stats.Moved++
                            
                        } catch {
                            $Stats.Errors++
                            Write-Host "`n  $($Global:Icons.Error) Failed to move '$($File.Name)': $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
            }
    }
    Write-Host "    $($Global:Icons.Check) Sorted $SortedCount files into month folders." -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Check) Archive Sync: Scanned=$($Stats.Scanned) Moved=$($Stats.Moved) Errors=$($Stats.Errors)" -ForegroundColor Green
}