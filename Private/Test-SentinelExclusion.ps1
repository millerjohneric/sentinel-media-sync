function Global:Test-SentinelExclusion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [string[]]$ExclusionPatterns = @('_Archive', '_log', '\.git', '\.vscode', 'thumbs\.db', 'desktop\.ini')
    )

    if ($Global:Config -and $Global:Config.Settings -and $Global:Config.Settings.Exclusions) {
        $ExclusionPatterns += $Global:Config.Settings.Exclusions
    }

    foreach ($Pattern in $ExclusionPatterns) {
        if ($FullPath -match $Pattern) {
            return $true
        }
    }

    return $false
}