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

    $DryRun   = $Settings.DryRun
    $ImgExts  = $FileTypes.Images
    $RawExts  = $FileTypes.RAWs
    $VidExts  = $FileTypes.Videos
    $AudExts  = $FileTypes.Audio
    $JunkList = $FileTypes.Junk

    $SkipSidecars = $Settings.DisableSidecarReunion -eq $true -or $Settings.DisableSidecarReunion -eq 'true'
    $SkipJunk     = $Settings.DisableJunkPurge -eq $true -or $Settings.DisableJunkPurge -eq 'true'

    # Exclude .xmp sidecars from routing when sidecar processing is disabled
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

        $Files = Get-ChildItem -Path $Loc.Path -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $AllMedia -contains $_.Extension.ToLower() }

        $Total = $Files.Count
        $Count = 0

        foreach ($File in $Files) {
            $Stats.Scanned++
            $Count++
            $Ext = $File.Extension.ToLower()

            if (Test-SentinelExclusion -FullPath $File.FullName) { continue }

            $FileDate = if ($File.Name -match '(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})') {
                try { Get-Date -Year $Matches.y -Month $Matches.m -Day $Matches.d -Hour 0 -Minute 0 -Second 0 }
                catch { $File.CreationTime }
            } else { $File.CreationTime }

            $DateFolder = Join-Path -Path $FileDate.ToString('yyyy') -ChildPath $FileDate.ToString('MM MMMM')

            $TargetRoot = $null
            if ($RawExts -contains $Ext) { $TargetRoot = $RawLoc?.Path }
            elseif ($VidExts -contains $Ext) { $TargetRoot = $VideoLoc?.Path }
            elseif ($AudExts -contains $Ext) { $TargetRoot = $AudioLoc?.Path }
            elseif ($ImgExts -contains $Ext -or (-not $SkipSidecars -and $Ext -eq '.xmp')) { $TargetRoot = $TimelineLoc?.Path }

            if ([string]::IsNullOrWhiteSpace($TargetRoot)) { continue }

            $Destination = Join-Path -Path $TargetRoot -ChildPath $DateFolder
            Write-SentinelOdometer -Tag "ROUTE" -Source $Loc.Name -Path $File.Name -Current $Count -Total $Total

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
            $Sidecars = Get-ChildItem -Path $ArchiveLoc.Path -Filter *.xmp -Recurse -ErrorAction SilentlyContinue
            $TotalSidecars = $Sidecars.Count
            $CurrentSidecar = 0

            foreach ($S in $Sidecars) {
                $CurrentSidecar++
                Write-SentinelOdometer -Tag "REUNITE" -Source $ArchiveLoc.Name -Path $S.Name -Current $CurrentSidecar -Total $TotalSidecars

                try {
                    $Buddy = Get-SentinelBuddy -Sidecar $S -SearchRoot $ArchiveLoc.Path -ErrorAction Stop
                    
                    if ($Buddy -and $Buddy.NeedsReunion) {
                        if (-not $DryRun) {
                            Move-Item -Path $S.FullName -Destination $Buddy.Target -Force -ErrorAction Stop
                        }
                        $Stats.Reunited++
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
            Get-ChildItem -Path $Loc.Path -Recurse -File -ErrorAction SilentlyContinue |
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
                $LooseFiles = Get-ChildItem -Path $YearDir -File -ErrorAction SilentlyContinue

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