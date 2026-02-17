# ==============================================================================
# Sentinel Web Gen v20.16 [FULL MISSION COMPLETION]
# ==============================================================================
# --- BOOTSTRAP LIBRARY ---
$CorePath = Join-Path $PSScriptRoot "Sentinel-Core.ps1"
if (Test-Path $CorePath) {
    . $CorePath  # The 'dot' and space before the path is critical!
    Write-Host "  $($Global:Icons.Check) Core Library Loaded." -ForegroundColor Gray
} else {
    Write-Error "CRITICAL: Sentinel-Core.ps1 not found at $CorePath"
    exit
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()


# --- PHASE 0: RAW-SCAN EXTRACTION ---
Write-Host "PHASE 0: Scanning YAML (Raw String Mode)..." -ForegroundColor Cyan

# Read the file as raw text to bypass parser mapping issues
$RawYaml = Get-Content (Join-Path $PSScriptRoot 'Sentinel-Config.yml') -Raw
$TargetWebsitePath = $null

# Split the YAML into individual Location blocks
# We split by the dash at the start of a line which denotes a new list item
$Blocks = $RawYaml -split '(?m)^\s*-\s+'

foreach ($Block in $Blocks) {
    # Check if this specific block contains the web-root marker
    if ($Block -match "'RootType':\s*'web-root'") {
        # Extract the SitePath value from this specific block using Regex
        if ($Block -match "'SitePath':\s*'([^']+)'") {
            $TargetWebsitePath = $Matches[1]
            Write-Host "  $($Global:Icons.Check) Found Engine Path: $TargetWebsitePath" -ForegroundColor Gray
            break
        }
    }
}

# Fallback: If Regex fails, try the standard object if it somehow worked
if (-not $TargetWebsitePath -and $YamlData.Locations) {
    $Root = $YamlData.Locations | Where-Object { $_."'RootType'" -eq 'web-root' -or $_.RootType -eq 'web-root' }
    $TargetWebsitePath = if ($Root) { ($Root."'SitePath'" -split "'")[0] } else { $null }
}

if ([string]::IsNullOrWhiteSpace($TargetWebsitePath)) {
    Write-Error "CRITICAL: Could not find 'web-root' SitePath. Ensure 'RootType': 'web-root' is defined in the YAML."
    exit
}

# Standardize the path for Windows
$TargetWebsitePath = $TargetWebsitePath.Replace("'", "").Trim()
if ($null -eq $YamlData) {
    # If you are using a YAML module like powershell-yaml or similar:
    $YamlData = Get-Content (Join-Path $PSScriptRoot 'Sentinel-Config.yml') -Raw | ConvertFrom-Yaml
}
# --- PHASE 0: READYNESS ---
Initialize-SentinelSecrets
# --- PHASE 1: ENSURING ENGINE INTEGRITY ---
if ($YamlData.Settings.PurgeWebsite -and (Test-Path $TargetWebsitePath)) {
    Write-Host "  $($Global:Icons.Warning) PurgeWebsite is TRUE: Wiping engine..." -ForegroundColor Yellow
    Remove-Item $TargetWebsitePath -Recurse -Force
}

if (!(Test-Path $TargetWebsitePath)) {
    Write-Host "  $($Global:Icons.Warning) Engine missing. Scaffolding..." -ForegroundColor Yellow
    # Create the parent directory if it doesn't exist
    $ParentDir = Split-Path $TargetWebsitePath
    if (!(Test-Path $ParentDir)) { New-Item $ParentDir -ItemType Directory -Force }

    # Run the scaffold command ONE level up
    Set-Location $ParentDir
    npx create-docusaurus@latest website classic --javascript --skip-install

    # Now that the folder exists, move into it and install
    Set-Location $TargetWebsitePath
    npm install
}
Purge-SentinelBoilerplate -SitePath $CleanPath

# --- PHASE 2: GENERATING ARCHITECTURE ---
Write-Host "`nPHASE 2: Injecting Dynamic Plugins..." -ForegroundColor Cyan
Write-SentinelDocusaurusConfig -SitePath $TargetWebsitePath -Locations $YamlData.Locations
Write-SentinelSidebars -SitePath $TargetWebsitePath -Locations $YamlData.Locations

# --- PHASE 2: TEMPLATE GENERATION & INJECTION ---
# 1. Update your GitHub templates folder (Dev Mode)
Initialize-SentinelTemplates -TemplateDir $YamlData.Settings.TemplateDir

# 2. Inject those templates into the Sandbox (Build Mode)
Invoke-SentinelBranding -SitePath $TargetWebsitePath -TemplateDir $YamlData.Settings.TemplateDir

# --- PHASE 2: CONTENT SYNC (The Safe Copy) ---
Write-Host "PHASE 2: Selective Content Sync..." -ForegroundColor Cyan
$FileTypes = $YamlData.Settings.FileTypes
Sync-SentinelWebContent -Locations $YamlData.Locations -FileTypes $FileTypes
# --- PHASE 3: GENERATION ---
Write-Host "`nPHASE 3: Generating Web Architecture..." -ForegroundColor Cyan

$stats = @{ Scanned = 0; Created = 0; Updated = 0; Skipped = 0; Errors = 0 }
$AssetExts = Get-SentinelWebExtensions -FileTypeData $YamlData.FileTypes

foreach ($loc in $WebLocations) {
    # Skip the engine itself if it's already handled by the sync pass
    if ($loc.RootType -eq "web-root") { continue }

    $SandboxRoot = Join-Path $TargetWebsitePath $loc.WebSubFolder
    $AssetExts = Get-SentinelWebExtensions -FileTypeData $FileTypes

    Write-Host "  Processing Site: $($loc.Name)" -ForegroundColor Magenta

    # Group files by your GroupSeparator (e.g., -.-)
    $Groups = Get-ChildItem $SandboxRoot -Recurse -File | Group-Object {
        if ($_.BaseName -match "(.*)$([regex]::Escape($loc.GroupSeparator))") { $Matches[1] } else { $_.BaseName }
    }

    foreach ($group in $Groups) {
        $stats.Scanned++

        # Build-WebPageFromTemplate now creates the .mdx right next to the synced images
        $Result = Build-WebPageFromTemplate `
            -SourceFiles $group.Group `
            -TargetFolder $group.Group[0].DirectoryName `
            -AssetExts $AssetExts `
            -Overwrite $loc.Overwrite `
            -FolderName $group.Name `
            -RootType $loc.RootType

        switch ($Result) {
            'CREATED' { $stats.Created++ }
            'UPDATED' { $stats.Updated++ }
            'SKIPPED' { $stats.Skipped++ }
            default   { $stats.Errors++ }
        }

        # Odometer update (Using the count from Phase 0 or $Groups.Count)
        Write-SentinelOdometer -Tag 'GEN' -Source $loc.Name -Path $group.Name -Current $stats.Scanned -Total $Groups.Count -Time "00:00"
    }
}
# --- FINAL: UPDATE REGISTRY ---
$RegPath = Join-Path $YamlData.Settings.TemplateDir "core-config/nav-registry.json"
if (Test-Path $RegPath) {
    $Reg = Get-Content $RegPath | ConvertFrom-Json
    $Reg.lastUpdate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Reg.version = "20.16"
    $Reg | ConvertTo-Json | Out-File $RegPath -Encoding UTF8
    Write-Host "  $($Global:Icons.Check) Registry Updated: $($Reg.lastUpdate)" -ForegroundColor Gray
}

Clear-SentinelOdometer

# --- PHASE 4 & 5: REPORT & LAUNCH ---
Send-SentinelNotification -Stats $stats -Duration $globalStopwatch.Elapsed -JobName "Web Gen"
Start-SentinelWebsite -Path $TargetWebsitePath

$globalStopwatch.Stop()
Write-Host "`nMISSION COMPLETE. Closing in 5s (Site remains ONLINE)." -ForegroundColor Green
Start-Sleep -Seconds 5
exit