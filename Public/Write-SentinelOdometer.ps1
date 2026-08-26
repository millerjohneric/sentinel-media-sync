function Write-SentinelOdometer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Destination = "",

        [Parameter(Mandatory = $true)]
        [int]$Current,

        [Parameter(Mandatory = $true)]
        [int]$Total
    )

    $Percent = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100) } else { 0 }
    $BarWidth = 20
    $FilledWidth = [Math]::Floor(($Percent / 100) * $BarWidth)
    $EmptyWidth = $BarWidth - $FilledWidth
    $Bar = ('#' * $FilledWidth) + ('-' * $EmptyWidth)

    $DisplaySource = if ($Source.Length -gt 15) { $Source.Substring(0, 12) + "..." } else { $Source }
    $DisplayPath   = if ($Path.Length -gt 25) { "..." + $Path.Substring($Path.Length - 22) } else { $Path }

    $esc = [char]27

    # Make the filename/path clickable pointing back to the source if available, or just display it
    $DisplayDest = ""
    if (-not [string]::IsNullOrWhiteSpace($Destination)) {
        $destUri = "file:///" + ($Destination -replace '\\', '/')
        $VisualDest = if ($Destination.Length -gt 30) { 
            "..." + $Destination.Substring($Destination.Length - 27) 
        } else { 
            $Destination 
        }
        $destLink = "$esc]8;;$destUri$esc\$VisualDest$esc]8;;$esc\"
        $DisplayDest = " -> $destLink"
    }

    $LineOutput = "`r$esc[K  [{0}] [{1}] {2,3}% |{3}| ({4}/{5}) {6}{7}" -f `
        $Tag, `
        $DisplaySource.PadRight(15), `
        $Percent, `
        $Bar, `
        $Current, `
        $Total, `
        $DisplayPath.PadRight(25), `
        $DisplayDest

    if ($Current -ge $Total) {
        Write-Host $LineOutput -ForegroundColor Cyan
    } else {
        Write-Host $LineOutput -NoNewline -ForegroundColor Cyan
    }
}