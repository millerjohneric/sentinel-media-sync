function Global:Initialize-SentinelWebRoot {
    param([string]$BuildPath, [string]$DeployPath, $EngineLoc)
    Write-Host "  $($Global:Icons.Check) Initializing Web Root Structure..." -ForegroundColor Gray
    
    # Create the base directory if it doesn't exist
    if (!(Test-Path $DeployPath)) { 
        New-Item -Path $DeployPath -ItemType Directory -Force | Out-Null 
    }

    # These are the essential Docusaurus folders
    $Required = @("docs", "static", "src", "src/pages")
    foreach ($Folder in $Required) {
        $P = Join-Path $DeployPath $Folder
        if (!(Test-Path $P)) { 
            New-Item $P -ItemType Directory -Force | Out-Null 
            Write-Host "    + Created: $Folder" -ForegroundColor DarkGray
        }
    }
}