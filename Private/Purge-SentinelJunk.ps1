function Purge-SentinelJunk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Locations,

        [Parameter(Mandatory = $true)]
        [array]$Exclusions,

        [Parameter(Mandatory = $true)]
        [array]$JunkPatterns
    )

    Write-Host "`n   $($Global:Icons.Trash) Purging junk files..." -ForegroundColor Cyan
    $JunkCount = 0

    foreach ($loc in $Locations) {
        $targetPath = if ($loc.Path) { $loc.Path } elseif ($loc.SitePath) { $loc.SitePath } else { $loc.RootPath }

        if (-not $targetPath -or -not (Test-Path -Path $targetPath)) {
            continue
        }

        try {
            $dirInfo = New-Object System.IO.DirectoryInfo($targetPath)
            
            # 1. Purge specific junk files dynamically pulled from config
            foreach ($junkName in $JunkPatterns) {
                if ([string]::IsNullOrWhiteSpace($junkName)) { continue }
                
                $dirInfo.EnumerateFiles($junkName, [System.IO.SearchOption]::AllDirectories) | ForEach-Object {
                    try {
                        # Clear potential read-only attributes that block deletion
                        $_.Attributes = [System.IO.FileAttributes]::Normal
                        Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                        $JunkCount++
                    } catch {
                        # Safely bypass locked or open files without halting execution
                    }
                }
            }

            # 2. Clean empty junk directories bottom-up with multiple passes to ensure parents clear out
            for ($i = 0; $i -lt 2; $i++) {
                $dirInfo.EnumerateDirectories("*", [System.IO.SearchOption]::AllDirectories) | 
                    Sort-Object FullName -Descending | ForEach-Object {
                        try {
                            if ($_.GetFileSystemInfos().Count -eq 0) {
                                Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction Stop
                            }
                        } catch {
                            # Bypass permission restrictions safely
                        }
                    }
            }
        } catch {
            Write-Host "   $($Global:Icons.Warning) Skipped unreadable path: $targetPath" -ForegroundColor Yellow
        }
    }

    Write-Host "    $($Global:Icons.Check) Junk purged: $JunkCount items cleaned." -ForegroundColor Gray
}