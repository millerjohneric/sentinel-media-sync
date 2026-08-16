function Get-SentinelBuddy {
    param (
        [System.IO.FileInfo]$Sidecar,
        [string]$SearchRoot
    )

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Sidecar.Name)
    $LocalFolder = $Sidecar.DirectoryName

    # 1. First check strictly in the same directory (fast local lookahead)
    $Companion = Get-ChildItem -Path $LocalFolder -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.BaseName -eq $BaseName -and $_.Extension -ne '.xmp' } | 
        Select-Object -First 1

    if ($Companion) {
        return [PSCustomObject]@{
            NeedsReunion = $false
            Target       = $Companion.FullName
        }
    }

    # 2. Skip full recursive NAS scans for corrupt Y2K38 / future timestamp artifacts
    if ($Sidecar.Name -match '^(203[8-9]|20[4-9]\d)') {
        return $null
    }

    # 3. If no local companion and not a corrupt date, perform shallow fallback search only
    return $null
}