function Get-SentinelRevision {
    param([string]$ScriptPath)
    $VersionFile = Join-Path $ScriptPath ".sentinel_version"
    $BaseVersion = "20" # Your current major version
    
    if (Test-Path $VersionFile) {
        $Rev = [int](Get-Content $VersionFile) + 1
    } else {
        $Rev = 1
    }
    
    $Rev | Out-File $VersionFile -Encoding utf8
    return "v$BaseVersion.$Rev"
}
