function Get-SentinelGalleryData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    $xmpPath = [System.IO.Path]::ChangeExtension($ImagePath, '.xmp')
    if (-not (Test-Path -Path $xmpPath)) {
        return [PSCustomObject]@{
            FileName = Split-Path -Leaf $ImagePath
            Camera   = "Unknown"
            Lens     = "Unknown"
            Keywords = @()
        }
    }

    [xml]$xmp = Get-Content -Path $xmpPath

    return [PSCustomObject]@{
        FileName = Split-Path -Leaf $ImagePath
        Camera   = $xmp.SelectNodes("//tiff:Model") | Select-Object -ExpandProperty '#text'
        Lens     = $xmp.SelectNodes("//aux:Lens") | Select-Object -ExpandProperty '#text'
        Keywords = $xmp.SelectNodes("//dc:subject/rdf:Bag/rdf:li") | Select-Object -ExpandProperty '#text'
    }
}