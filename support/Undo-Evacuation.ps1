# Separate script: Undo-Evacuation.ps1
$recoveryLog = Join-Path $PSScriptRoot "recovery_map.csv"
if (Test-Path $recoveryLog) {
    Import-Csv $recoveryLog -Header "Archive","Original" | ForEach-Object {
        if (Test-Path $_.Archive) {
            Move-Item $_.Archive $_.Original -Force
            Write-Host "Restored: $($_.Original)"
        }
    }
    Remove-Item $recoveryLog
}