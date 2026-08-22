function Write-SentinelPhase0 {
    param($YamlData)
    $Locs = if ($YamlData.Locations) { $YamlData.Locations } else { $YamlData.locations }
    
    $MaxName = ($Locs.Name | Measure-Object -Property Length -Maximum).Maximum + 2
    $MaxRole = ($Locs.Role | Measure-Object -Property Length -Maximum).Maximum + 2
    if ($MaxName -lt 15) { $MaxName = 15 }

    # FIX: Define the string first, then write it with the color
    $HeaderText = "     {0,-10} {1,-$MaxName} {2,-$MaxRole} {3}" -f "STATUS", "NAME", "ROLE", "PATH"
    Write-Host $HeaderText -ForegroundColor Gray

    foreach ($loc in $Locs) {
        $Status = "ACTIVE"; $Color = "White"
        switch -Regex ($loc.Role) {
            "Website"         { $Status = "TARGET"; $Color = "Yellow" }
            "Pickup"          { $Color = "Green" }
            "Archive"         { $Color = "Gray" }
            "InPlace_Archive" { $Color = "Magenta" }
            "timeline"        { $Color = "Cyan" }
        }
        if (!(Test-Path $loc.Path)) { $Status = "OFFLINE"; $Color = "Red" }
        
        $RowText = "     [{0,-8}] [{1,-$MaxName}] [{2,-$MaxRole}] {3}" -f $Status, $loc.Name, $loc.Role, $loc.Path
        Write-Host $RowText -ForegroundColor $Color
    }
}
