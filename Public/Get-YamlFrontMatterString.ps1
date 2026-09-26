function Get-YamlFrontMatterString {
    param (
        [string]$Title,
        [array]$Tags,
        [hashtable]$ExtraFields = @{}
    )
    $cleanTitle = $Title -replace "'", "''"
    $lines = @("---", "title: '$cleanTitle'")

    foreach ($key in $ExtraFields.Keys) {
        $val = $ExtraFields[$key]
        $cleanVal = if ($null -ne $val) { $val.ToString() -replace "'", "''" } else { "" }
        $lines += ("{0}: '{1}'" -f $key, $cleanVal)
    }

    if ($Tags -and $Tags.Count -gt 0) {
        $formattedItems = $Tags | ForEach-Object {
            $tagStr = $_.ToString().Trim() -replace "'", "''"
            "'$tagStr'"
        }
        $lines += ("tags: [{0}]" -f ($formattedItems -join ", "))
    } else {
        $lines += "tags: []"
    }

    $lines += "---"
    return ($lines -join "`n")
}