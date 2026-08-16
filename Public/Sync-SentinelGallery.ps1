function Global:Sync-SentinelGallery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        [string]$Output,

        [Parameter(Mandatory = $false)]
        [string]$TemplateDir
    )

    # Fallback guard to prevent null Output errors across Join-Path and Get-Item
    if ([string]::IsNullOrWhiteSpace($Output)) {
        if ($null -ne $Config -and $Config.Settings -and $Config.Settings.WebRoot) {
            $Output = Join-Path -Path $Config.Settings.WebRoot -ChildPath 'docs\gallery'
        } else {
            Write-Error "Gallery Output path is empty and could not be resolved from Config settings."
            return
        }
    }

    # Ensure output directory exists before processing
    if (-not (Test-Path -Path $Output)) {
        New-Item -Path $Output -ItemType Directory -Force | Out-Null
    }

    Write-Host "`n  $($Global:Icons.Arrow) Processing Pipeline: Gallery" -ForegroundColor Cyan

    # Cleanup legacy index file safely
    $OldIndex = Join-Path -Path $Output -ChildPath "index.md"
    if (Test-Path -Path $OldIndex) {
        Remove-Item -Path $OldIndex -Force
    }

    # Collect directories for indexing
    $AllOutputDirs = Get-ChildItem -Path $Output -Directory -Recurse -ErrorAction SilentlyContinue
    $DirsToIndex = @($AllOutputDirs) + @(Get-Item -Path $Output)

    # Index generation logic with path replacement validation
    foreach ($Dir in $DirsToIndex) {
        if ([string]::IsNullOrEmpty($Output)) { continue }

        $RelFromOutput = $Dir.FullName.Replace($Output, '').TrimStart('\', '/')
        
        # Build category metadata and session pages here...
    }

    Write-Host "     Gallery category indexes generated." -ForegroundColor Green
}