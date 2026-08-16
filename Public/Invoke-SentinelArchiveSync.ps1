function Invoke-SentinelArchiveSync {
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
    
    # Ensure $FileDate has a valid fallback before formatting
    if (-not $FileDate) {
        $FileDate = (Get-Date)
    }

    # Translate config format tokens into C#/.NET date patterns safely
    $DotNetFormat = if ($ConfigFormat) {
        $ConfigFormat -replace '%Y', 'yyyy' -replace '%m', 'MM' -replace '%d', 'dd' -replace '%B', 'MMMM'
    } else {
        'yyyy/yyyy-MM MMMM'
    }
    
    # Calculate path based on configuration format
    $DateFolder = if ($DotNetFormat -match '/') {
        $Parts = $DotNetFormat.Split('/', 2)
        $YearPart = $FileDate.ToString($Parts[0])
        $SubPart  = $FileDate.ToString($Parts[1])
        Join-Path -Path $YearPart -ChildPath $SubPart
    } else {
        $FileDate.ToString($DotNetFormat)

    $DryRun   = $Settings.DryRun
    
    # Force lowecase and leading dots on all input extensions
    $ImgExts  = @($FileTypes.Images) | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { $_.ToLower() }
    $RawExts  = @($FileTypes.RAWs)   | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { $_.ToLower() }
    $VidExts  = @($FileTypes.Videos) | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { $_.ToLower() }
    $AudExts  = @($FileTypes.Audio)  | ForEach-Object { if ($_ -and -not $_.StartsWith('.')) { ".$_" } else { $_ } } | ForEach-Object { $_.ToLower() }
    $JunkList = $FileTypes.Junk

    # Fallback default image extensions if YAML hashtable failed to load Images key
    if (-not $ImgExts -or $ImgExts.Count -eq 0) {
        $ImgExts = @('.png', '.jpg', '.jpeg', '.gif', '.bmp')
    }
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
        # DIAGNOSTIC CHECK
        $RawFiles = Get-ChildItem -Path $Loc.Path -File -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  -> Checking $($Loc.Name): Found $($RawFiles.Count) total raw files in path: $($Loc.Path)" -ForegroundColor Yellow

        $Files = $RawFiles | Where-Object { $AllMedia -contains $_.Extension.ToLower() }
        Write-Host "     After extension filter ($($AllMedia -join ', ')): Matched $($Files.Count) files." -ForegroundColor Yellow
        # Added -Force to capture hidden/system screenshot files from SnippingTool
        $Files = Get-ChildItem -Path $Loc.Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $AllMedia -contains $_.Extension.ToLower() }

        $Total = $Files.Count
        $Count = 0

        foreach ($File in $Files) {
            $Stats.Scanned++
            $Count++
            $Ext = $File.Extension.ToLower()

            if (Get-Command -Name Test-SentinelExclusion -ErrorAction SilentlyContinue) {
                if (Test-SentinelExclusion -FullPath $File.FullName) { continue }
            }

            $FileDate = if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                try { Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 }
                catch { $File.CreationTime }
            } else { $File.CreationTime }
            # Ensure $FileDate has a fallback if parsing failed
            if (-not $FileDate) {
                $FileDate = $File.CreationTime
            }

            # Translate config format tokens into C#/.NET date patterns
            $DotNetFormat = $ConfigFormat -replace '%Y', 'yyyy' -replace '%m', 'MM' -replace '%d', 'dd' -replace '%B', 'MMMM'
            
            # If the format includes a slash, split it into Year and Subfolder parts
            if ($DotNetFormat -match '/') {
                $Parts = $DotNetFormat.Split('/', 2)
                $YearPart = $FileDate.ToString($Parts[0])
                $SubPart  = $FileDate.ToString($Parts[1])
                $DateFolder = Join-Path -Path $YearPart -ChildPath $SubPart
            } else {
                $DateFolder = $FileDate.ToString($DotNetFormat)
            }
            # Translate config format tokens into C#/.NET date patterns
            $DotNetFormat = $ConfigFormat -replace '%Y', 'yyyy' -replace '%m', 'MM' -replace '%d', 'dd' -replace '%B', 'MMMM'
            
            # If the format includes a slash, split it into Year and Subfolder parts
            if ($DotNetFormat -match '/') {
                $Parts = $DotNetFormat.Split('/', 2)
                $YearPart = $FileDate.ToString($Parts[0])
                $SubPart  = $FileDate.ToString($Parts[1])
                $DateFolder = Join-Path -Path $YearPart -ChildPath $SubPart
            } else {
                $DateFolder = $FileDate.ToString($DotNetFormat)
            }
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
                    if (-not (Test-Path -Path $Destination)) { New-Item -Path $Destination -ItemType Directory -Force | Out-Null }
                    $DestFile = Join-Path -Path $Destination -ChildPath $File.Name
                    if (-not (Test-Path -Path $DestFile)) {
                        Move-Item -Path $File.FullName -Destination $Destination -Force -ErrorAction Stop
                        $Stats.Moved++
                    }
                } catch {
                    $Stats.Errors++
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
                    Write-SentinelOdometer -Tag "REUNITE" -Source $ArchiveLoc.Name -Path $S.Name -Current $CurrentSidecar -Total $TotalSidecars
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

    # --- JUNK PURGE PHASE ---
    if (-not $SkipJunk -and $JunkList) {
        Write-Host "  $($Global:Icons.Arrow) Purging junk files..." -ForegroundColor Gray
        $JunkCount = 0
        foreach ($Loc in $ArchiveLocs) {
            if (-not (Test-Path -Path $Loc.Path)) { continue }
            Get-ChildItem -Path $Loc.Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $JunkList -contains $_.Name } |
                ForEach-Object {
                    if (-not $DryRun) {
                        try { Remove-Item -Path $_.FullName -Force -ErrorAction Stop; $JunkCount++; $Stats.Purged++ } catch {}
                    }
                }
        }
        Write-Host "    $($Global:Icons.Check) Junk purged: $JunkCount files." -ForegroundColor Gray
    } else {
        Write-Host "  $($Global:Icons.Check) Junk purge skipped per configuration." -ForegroundColor Gray
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

                    $FileDate = if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                        try { Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 }
                        catch { $File.CreationTime }
                    } else { $File.CreationTime }

                    $MonthFolder = Join-Path -Path $YearDir -ChildPath $FileDate.ToString('MM MMMM')

                    if (-not $DryRun) {
                        try {
                            if (-not (Test-Path -Path $MonthFolder)) { New-Item -Path $MonthFolder -ItemType Directory -Force | Out-Null }
                            $Dest = Join-Path -Path $MonthFolder -ChildPath $File.Name
                            if (-not (Test-Path -Path $Dest)) {
                                Move-Item -Path $File.FullName -Destination $MonthFolder -Force -ErrorAction Stop
                                $SortedCount++
                            }
                        } catch { $Stats.Errors++ }
                    }
                }
            }
    }
    Write-Host "    $($Global:Icons.Check) Sorted $SortedCount files into month folders." -ForegroundColor Gray
    Write-Host "  $($Global:Icons.Check) Archive Sync: Scanned=$($Stats.Scanned) Moved=$($Stats.Moved) Errors=$($Stats.Errors)" -ForegroundColor Green
}