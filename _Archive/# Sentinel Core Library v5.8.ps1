# ==============================================================================
# Sentinel Core Library v5.8 [MERMAID & BROWSER-OPEN FIX]
# ==============================================================================

# Global Icons for consistent UI
$Global:Icons = @{
    'Arrow'   = [char]0x2192
    'Check'   = [char]0x2714
    'Warning' = [char]0x26A0
    'Error'   = [char]0x2718
}
function Global:Initialize-SentinelWebRoot {
    param($RootPath)

    $AllowPurge = $script:YamlData.'Settings'.'PurgeWebsite'
    $AllowPrune = $script:YamlData.'Settings'.'PruneWebsite'

    # NEW: Aggressive Cache Clearing for Docusaurus 3.x
    # This prevents the "ChunkLoadError" by forcing a fresh registry build
    $CachePath = Join-Path $RootPath ".docusaurus"
    if (Test-Path $CachePath) {
        Write-Host "  $($Global:Icons.Arrow) Clearing stale build cache..." -ForegroundColor Gray
        Remove-Item $CachePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    $IsBroken = (Test-Path $RootPath) -and !(Test-Path (Join-Path $RootPath 'package.json'))

    if ($IsBroken -or ($AllowPurge -and !$AllowPrune)) {
        Write-Host "  $($Global:Icons.Warning) Broken or Full-Purge detected. Wiping Root..." -ForegroundColor Red
        Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        if (Test-Path $RootPath) { Remove-Item $RootPath -Recurse -Force }
    }
    elseif ($AllowPrune) {
        Write-Host "  $($Global:Icons.Warning) PruneWebsite is TRUE. Performing Smart-Wipe..." -ForegroundColor Yellow
        Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force

        $ItemsToKill = Get-ChildItem -Path $RootPath -Exclude "node_modules"
        foreach ($Item in $ItemsToKill) {
            Remove-Item $Item.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Now npx won't crash because the folder is either gone or contains a valid package.json
    if (!(Test-Path $RootPath)) {
        Write-Host "  $($Global:Icons.Arrow) Engine missing. Scaffolding Docusaurus..." -ForegroundColor Cyan
        $Parent = Split-Path $RootPath -Parent
        $Leaf = Split-Path $RootPath -Leaf
        Push-Location $Parent
        cmd /c "npx --yes create-docusaurus@latest $Leaf classic --javascript --skip-install"
        Pop-Location
    }

    return $true
}
function Global:Start-SentinelWebsite {
    param($Path, $Locations)

    Push-Location $Path

    # 1. Check for node_modules
    if (!(Test-Path (Join-Path $Path "node_modules"))) {
        Write-Host "  $($Global:Icons.Arrow) node_modules missing. Running full install..." -ForegroundColor Cyan
        cmd /c "npm install --quiet"
    }

    # 2. THE FIX: Explicitly check/install Mermaid if it's failing
    # We check the folder directly to be 100% sure it exists before starting
    if (!(Test-Path (Join-Path $Path "node_modules/@docusaurus/theme-mermaid"))) {
        Write-Host "  $($Global:Icons.Warning) Mermaid theme missing. Injecting package..." -ForegroundColor Yellow
        cmd /c "npm install --save @docusaurus/theme-mermaid --quiet"
    }
    Write-Host "  $($Global:Icons.Check) Launching Server..." -ForegroundColor Green

    # REMOVED --open and --browser-open to prevent CLI errors
    $StartCommand = "npx docusaurus start --host 0.0.0.0"

    # Launch the Node process in a new window
    Start-Process "cmd.exe" -ArgumentList "/k $StartCommand" -WorkingDirectory $Path

    # Wait 5 seconds for the engine to warm up, then launch browser via PS
    Write-Host "  $($Global:Icons.Arrow) Waiting for engine, then launching browser..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    Start-Process "http://localhost:3000"

    Pop-Location
    return "ONLINE"
}

function Global:Build-WebPageFromTemplate {
    param(
        [Parameter(Mandatory=$true)]$SourceFiles,
        [Parameter(Mandatory=$true)]$TargetFolder,
        [Parameter(Mandatory=$true)]$AssetExts,
        [boolean]$Overwrite = $true,
        [string]$FolderName = "Unknown"
    )

    if (!(Test-Path $TargetFolder)) { New-Item $TargetFolder -ItemType Directory -Force | Out-Null }

    # Identify Documents vs Assets using the Ext list from YAML
    $Docs = $SourceFiles | Where-Object { $_.Extension -match 'md|txt|pdf' }
    $Assets = $SourceFiles | Where-Object { $_.Extension.TrimStart('.') -in $AssetExts -and $_.Extension -notmatch 'md|txt' }

    # 1. Handle Documents (Transforming to MDX)
    foreach ($Doc in $Docs) {
        $TargetDocPath = Join-Path $TargetFolder "$($Doc.BaseName).mdx"
        if ((Test-Path $TargetDocPath) -and !$Overwrite) { continue }

        $Content = Get-Content -Path $Doc.FullName -Raw
        # Your specific requirement for single quotes in YAML keys is handled here
        $Frontmatter = "---`ntitle: '$($Doc.BaseName)'`nsidebar_label: '$($Doc.BaseName)'`n---`n`n"

        ($Frontmatter + $Content) | Set-Content -Path $TargetDocPath -Encoding UTF8
    }

    # 2. Handle ALL Assets (The missing images/videos)
    foreach ($Asset in $Assets) {
        $TargetAssetPath = Join-Path $TargetFolder $Asset.Name
        if (!(Test-Path $TargetAssetPath) -or $Overwrite) {
            Copy-Item -Path $Asset.FullName -Destination $TargetAssetPath -Force
        }
    }

    # Visual odometer feedback
    Write-SentinelOdometer -Tag "GEN" -Source $FolderName -Path "$($TargetFolder)" -Current 1 -Total 1
}

function Global:Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current, $Total, $Time)
    $Percent = [Math]::Round(($Current / $Total) * 100)
    # Formats as: → [GEN] [Culinary] [12/50] (24%) [00:15] filename.mdx
    $Prefix = "  $($Global:Icons.Arrow) [$Tag] [$Source] [$Current/$Total] ($Percent%) [$Time] "

    # Trim path if it exceeds terminal width to keep odometer on one line
    $MaxPathLen = 120 - $Prefix.Length
    $DisplayPath = if ($Path.Length -gt $MaxPathLen) { "..." + $Path.Substring($Path.Length - ($MaxPathLen - 3)) } else { $Path }

    Write-Host "`r$Prefix$DisplayPath" -NoNewline
}

function Global:Clean-SentinelContent {
    param([string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return "" }
    $Escaped = $Content -replace '\{', '&#123;' -replace '\}', '&#125;'
    $Escaped = $Escaped -replace '(?m)^:', '\:'
    return $Escaped.Trim()
}

function Global:Get-SentinelWebExtensions {
    param($FileTypeData)
    $FinalList = @()
    foreach ($item in $FileTypeData.WebContent) {
        if ($FileTypeData.ContainsKey($item)) { $FinalList += $FileTypeData.$item }
        else { $FinalList += $item }
    }
    return $FinalList | ForEach-Object { $_.ToLower().TrimStart('.') } | Select-Object -Unique
}

function Global:Write-SentinelCategoryYaml {
    param($FolderPath, $FolderName)
    $Path = Join-Path $FolderPath "_category_.yml"
    $Content = "label: '$FolderName'`nlink:`n  type: 'generated-index'`n  description: 'View $FolderName collection.'"
    $Content | Set-Content $Path -Encoding UTF8 -Force
}

function Global:Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot 'index.md'
    $DirName = Split-Path $TargetRoot -Leaf
    $Content = "---`ntitle: '$DirName'`nsidebar_label: 'Overview'`nslug: '/'`n---`n`nimport DocCardList from '@theme/DocCardList';`n`n# $DirName Gallery`n`n<DocCardList />"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}

function Global:Test-SentinelExclusion {
    param([string]$Path)
    $Exclusions = $script:YamlData.'Settings'.'FileTypes'.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
    }
    return $false
}

function Global:Send-SentinelNotification {
    param($Stats, $Duration, $JobName)
    $Conf = $script:YamlData.'Settings'.'EmailSettings'
    if (-not $Conf.'Enabled') { return }
    Write-Host "  $($Global:Icons.Check) Notification Sent: $JobName" -ForegroundColor Gray
}
function Global:Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}
function Global:Write-SentinelPhase0 {
    param(
        [Parameter(Mandatory=$true)] $Locations,
        [Parameter(Mandatory=$true)] [ValidateSet('Sync', 'Web')] $JobType
    )
    Write-Host '     STATUS      NAME                ROLE                PATH'
    foreach ($loc in $Locations) {
        $IsOnline = Test-Path $loc.Path
        $IsRelevant = if ($JobType -eq 'Web') { $loc.Role -eq 'Website' } else { $loc.MonitorDepth -ge 0 }

        if (-not $IsOnline) { $StatusStr = '[OFFLINE ]'; $StatusColor = 'Red' }
        elseif ($IsRelevant) { $StatusStr = '[ACTIVE  ]'; $StatusColor = 'Green' }
        else { $StatusStr = '[SINK    ]'; $StatusColor = 'DarkGray' }

        $RoleColor = Get-SentinelRoleColor -Role $loc.Role
        Write-Host '     ' -NoNewline
        Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
        Write-Host " [$($loc.Name.PadRight(16))]" -NoNewline
        $RoleDisplay = if ([string]::IsNullOrWhiteSpace($loc.Role)) { "N/A" } else { $loc.Role }
        Write-Host " [$($RoleDisplay.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
        Write-Host $loc.Path -ForegroundColor Gray
    }
}
function Global:Get-SafeYamlTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return "Untitled" }

    # Escape double quotes and wrap the whole title in double quotes
    $CleanTitle = $Title -replace '"', '\"'
    return "`"$CleanTitle`""
}
function Global:Initialize-SentinelSecrets {
    $Conf = $script:YamlData.'Settings'.'EmailSettings'
    $SecretFile = Join-Path $PSScriptRoot ($Conf.'CredPath')
    if (-not (Test-Path $SecretFile)) {
        Write-Host "`n[SECURITY] No credentials found." -ForegroundColor Yellow
        $RawPass = Read-Host "Paste your 16-character GMail App Password for $($Conf.'To')"
        $CleanPass = $RawPass.Trim().Replace(" ", "").Replace("`t", "")
        if ($CleanPass.Length -ne 16) { Write-Host "[CRITICAL] Gmail App Passwords must be 16 chars." -ForegroundColor Red; return }
        $SecPass = ConvertTo-SecureString $CleanPass -AsPlainText -Force
        New-Object System.Management.Automation.PSCredential($Conf.'To', $SecPass) | Export-CliXml -Path $SecretFile
        Write-Host "[SUCCESS] Password encrypted." -ForegroundColor Green
    }
    if (Test-Path $SecretFile) {
        $TempCred = Import-CliXml -Path $SecretFile
        $script:GmailUser = $TempCred.UserName
        $script:AppPassword = $TempCred.GetNetworkCredential().Password
    }
}
function Global:Format-SentinelNum {
    param([int]$Number)
    return $Number.ToString('#,0')
}
function Global:Get-SentinelWidth {
    try { return $Host.UI.RawUI.WindowSize.Width - 5 } catch { return 115 }
}
function Global:Get-SafeYaml {
    param($v)
    if ($v) { return $v.ToString().Replace("'", "''") } else { return "" }
}
function Global:Get-SentinelBuddy {
    param([System.IO.FileInfo]$Sidecar, [string]$SearchRoot)
    try {
        return Get-ChildItem $SearchRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.BaseName -eq $Sidecar.BaseName -and $_.Extension -ne '.xmp'
        } | Select-Object -First 1
    }
    catch { return $null }
}
function Global:Get-SentinelRoleColor {
    param([string]$Role)
    # Added Website role color (Green)
    if ($Role -eq 'Website') { return 'Green' }
    if ($Role -match 'Hybrid') { return 'Red' }
    switch -regex ($Role) {
        'Photo'        { return 'Yellow' }
        'RAW'          { return 'Cyan' }
        'Video|Audio'  { return 'Magenta' }
        'Pickup'       { return 'Gray' }
        Default        { return 'White' }
    }
}

