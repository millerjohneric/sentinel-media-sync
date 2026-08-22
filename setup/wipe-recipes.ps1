# ==============================================================================
# Recipe Cleanup Tool - Safety Version
# ==============================================================================


[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host " [!] ATTENTION: MUST COMMENT OUT 'EXIT' IN THE SCRIPT TO RUN." -ForegroundColor Yellow
Write-Host " [!] THIS ENSURES THE ACTION IS INTENTIONAL." -ForegroundColor Yellow
exit

$TargetDir = "H:\MakeMeASammich\website\docs\recipes"

Write-Host "⚠️  Preparing to delete generated Markdown files in $TargetDir" -ForegroundColor Yellow
$Confirm = Read-Host "Are you sure? (y/n)"

if ($Confirm -eq "y") {
    # Find all .md files and delete them
    $Files = Get-ChildItem -Path $TargetDir -Filter "*.md" -Recurse
    foreach ($File in $Files) {
        Remove-Item $File.FullName -Force
        # Using subexpression logic to match your working compiler style
        Write-Host "  [DELETED] $($File.Name)" -ForegroundColor Red
    }
    Write-Host "✨ Cleanup complete. Your recipe folders are ready for a fresh compile." -ForegroundColor Cyan
} else {
    Write-Host "❌ Cleanup cancelled." -ForegroundColor Gray
}