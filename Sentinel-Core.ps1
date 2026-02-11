# ==============================================================================
# Sentinel Core Library v3.0 (PS 5.1 Hardened)
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$Global:Icons = @{
    Arrow    = [char]0x2192
    Broom    = [char]0x232B
    Check    = [char]0x221A
}

function Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current = 0, $Total = 0)
    $Percent = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100) } else { 0 }

    $Width = Get-SentinelWidth
    # Construct the prefix (arrows and stats)
    $Prefix = "  $($Global:Icons.Arrow) [$Tag] [$Source] [$Current/$Total] ($Percent%) "

    # Calculate available space for the path to prevent wrapping
    $MaxPathLen = $Width - $Prefix.Length - 1
    $DisplayPath = if ($Path.Length -gt $MaxPathLen) {
        "..." + $Path.Substring($Path.Length - $MaxPathLen + 3)
    } else { $Path }

    # Return to start of line, print everything, then pad the remainder with spaces
    Write-Host "`r$Prefix" -NoNewline -ForegroundColor Cyan
    Write-Host $DisplayPath -NoNewline -ForegroundColor Gray

    $FinalLen = $Prefix.Length + $DisplayPath.Length
    $Padding = $Width - $FinalLen
    if ($Padding -gt 0) { Write-Host (" " * $Padding) -NoNewline }
}

function Get-SentinelWidth {
    $W = try { $Host.UI.RawUI.WindowSize.Width } catch { 120 }
    if ($W -lt 40) { $Result = 120 } else { $Result = $W - 5 }
    return $Result
}

function Format-SentinelNum {
    param([int]$Number)
    return $Number.ToString('#,0')
}

function Get-SentinelRoleColor {
    param([string]$Role)
    if ($Role -match 'Hybrid') { return 'Red' }
    switch -regex ($Role) {
        'Photo'        { return 'Yellow' }
        'RAW'          { return 'Cyan' }
        'Video|Audio'  { return 'Magenta' }
        'Pickup'       { return 'Gray' }
        Default        { return 'White' }
    }
}

# --- UI DISPLAY FUNCTIONS ---

function Write-SentinelPhase0 {
    param(
        [Parameter(Mandatory=$true)]
        $Locations,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Sync', 'Web')]
        $JobType
    )
    # Inside Write-SentinelPhase0 function in Sentinel-Core.ps1
    $IsRelevant = if ($JobType -eq 'Web') {
        $loc.Role -eq 'Hybrid_Archive'
    } else {
        # FIX: Use .Depth because that's where SentinelLocation class stores it
        $loc.Depth -ge 0
    }
    Write-Host '     STATUS      NAME                ROLE                PATH'
    foreach ($loc in $Locations) {
        $IsOnline = Test-Path $loc.Path

        # Determine Activity based on Job Context
        $IsRelevant = if ($JobType -eq 'Web') {
            $loc.Role -eq 'Hybrid_Archive'
        } else {
            # In Sync, we check if MonitorDepth is 0 or higher
            $loc.MonitorDepth -ge 0
        }

        # Status Logic
        if (-not $IsOnline) {
            $StatusStr = '[OFFLINE ]'
            $StatusColor = 'Red'
        } elseif ($IsRelevant) {
            $StatusStr = '[ACTIVE  ]'
            $StatusColor = 'Green'
        } else {
            $StatusStr = '[SINK    ]'
            $StatusColor = 'DarkGray'
        }

        $RoleColor = switch -regex ($loc.Role) {
            'Hybrid'      {'Red'}
            'Photo'       {'Yellow'}
            'RAW'         {'Cyan'}
            'Video|Audio' {'Magenta'}
            'Pickup'      {'Gray'}
            Default       {'White'}
        }

        Write-Host '     ' -NoNewline
        Write-Host $StatusStr.PadRight(12) -ForegroundColor $StatusColor -NoNewline
        Write-Host " [$($loc.Name.PadRight(16))]" -NoNewline
        $RoleDisplay = if ([string]::IsNullOrWhiteSpace($loc.Role)) { "N/A" } else { $loc.Role }
        Write-Host " [$($RoleDisplay.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
#        Write-Host " [$($loc.Role.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
        Write-Host $loc.Path -ForegroundColor Gray
    }
}

function Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}

# --- SECURITY & CREDENTIALS ---

function Initialize-SentinelSecrets {
    $Conf = $script:YamlData.'Settings'.'EmailSettings'
    $BaseDir = $PSScriptRoot
    $SecretFile = Join-Path $BaseDir ($Conf.'CredPath')

    if (-not (Test-Path $SecretFile)) {
        Write-Host "`n[SECURITY] No credentials found." -ForegroundColor Yellow
        $User = $Conf.'To'

        # User pastes password (e.g., 'pmkg igcu kstr kafj')
        $RawPass = Read-Host "Paste your 16-character GMail App Password for $User"

        # CLEANUP: Strip all spaces/tabs
        $CleanPass = $RawPass.Trim().Replace(" ", "").Replace("`t", "")

        if ($CleanPass.Length -ne 16) {
            Write-Host "`n[CRITICAL] Error: You provided $($CleanPass.Length) characters." -ForegroundColor Red
            Write-Host "Gmail App Passwords MUST be exactly 16 characters long." -ForegroundColor Red
            Write-Host "Please check your copy/paste and try again.`n" -ForegroundColor Yellow
            return # Exit function to prevent saving a broken password
        }

        $SecPass = ConvertTo-SecureString $CleanPass -AsPlainText -Force
        $Object = New-Object System.Management.Automation.PSCredential($User, $SecPass)
        $Object | Export-CliXml -Path $SecretFile
        Write-Host "[SUCCESS] 16-character password verified and encrypted." -ForegroundColor Green
    }

    if (Test-Path $SecretFile) {
        try {
            $TempCred = Import-CliXml -Path $SecretFile
            $script:GmailUser = $TempCred.UserName
            $script:AppPassword = $TempCred.GetNetworkCredential().Password
        } catch {
            Remove-Item $SecretFile -Force -ErrorAction SilentlyContinue
        }
    }
}


function Send-SentinelReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ReportBody,
        [string]$JobName = 'Sync',
        [string]$SiteUrl = ''  # New optional parameter
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Initialize-SentinelSecrets
    $Conf = $script:YamlData.'Settings'.'EmailSettings'
    if (-not $Conf.'Enabled' -or [string]::IsNullOrWhiteSpace($script:GmailUser)) { return }

    try {
        $Msg = New-Object System.Net.Mail.MailMessage
        $Msg.From = New-Object System.Net.Mail.MailAddress($script:GmailUser)
        $Msg.To.Add($Conf.'To')
        $Msg.Subject = "Sentinel $JobName Report: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

        # --- HTML Body Construction ---
        $Msg.IsBodyHtml = $true
        $HtmlBody = @"
<html>
<body style="font-family: sans-serif; line-height: 1.6; color: #333;">
    <h2 style="color: #2e8555;">Sentinel $JobName Report</h2>
    <pre style="background: #f4f4f4; padding: 15px; border-radius: 5px; border: 1px solid #ddd;">$ReportBody</pre>
"@
        # Append Link if SiteUrl is provided
        if (![string]::IsNullOrEmpty($SiteUrl)) {
            $HtmlBody += @"
    <div style="margin-top: 20px; padding: 15px; background: #e8f5e9; border-left: 5px solid #2e8555;">
        <strong>🌍 Live Site Updated:</strong><br />
        <a href="$SiteUrl" style="color: #2e8555; font-weight: bold; text-decoration: none;">$SiteUrl</a>
    </div>
"@
        }

        $HtmlBody += "</body></html>"
        $Msg.Body = $HtmlBody

        $Smtp = New-Object System.Net.Mail.SmtpClient('smtp.gmail.com', 587)
        $Smtp.EnableSsl = $true
        $Smtp.Timeout = 20000
        $Smtp.UseDefaultCredentials = $false
        $Smtp.Credentials = New-Object System.Net.NetworkCredential($script:GmailUser, $script:AppPassword)

        $Smtp.Send($Msg)
        Write-Host "`n[EMAIL] Success! Report sent to $($Conf.'To')" -ForegroundColor Green

        $Msg.Dispose(); $Smtp.Dispose()
    }
    catch {
        Write-Host "`n[EMAIL] AUTH FAILURE: Gmail rejected the credentials." -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Gray

        $Reset = Read-Host 'Reset credentials and try again? (Y/N)'
        if ($Reset -eq 'Y') {
            Remove-Item (Join-Path $PSScriptRoot $Conf.'CredPath') -Force -ErrorAction SilentlyContinue
        }
    }
}



# --- FILE LOGIC HELPERS ---

function Get-SentinelBuddy {
    param([System.IO.FileInfo]$Sidecar, [string]$SearchRoot)
    try {
        return Get-ChildItem $SearchRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.BaseName -eq $Sidecar.BaseName -and $_.Extension -ne '.xmp'
        } | Select-Object -First 1
    }
    catch { return $null }
}

# --- WEB GENERATION & TEMPLATE ENGINE ---


function Test-SentinelExclusion {
    param([string]$Path)
    $Exclusions = $script:YamlData.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
    }
    return $false
}

function Build-WebPageFromTemplate {
    param(
        [System.IO.FileInfo[]]$SourceFiles,
        [string]$TargetFolder,
        [string]$TemplateType,
        [bool]$Overwrite,
        [string]$GroupSeparator = '-.-'
    )

    if (-not $SourceFiles) { return 'ERROR' }

    # 1. Prepare Target Directory
    if (-not (Test-Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
    }

    # 2. Extract Primary Info
    $RawBase = $SourceFiles[0].BaseName
    $EscapedSep = [regex]::Escape($GroupSeparator)
    $CleanName = if ($RawBase -match $EscapedSep) {
        $RawBase.Substring(0, $RawBase.LastIndexOf($GroupSeparator))
    } else { $RawBase }

    $MdPath = Join-Path $TargetFolder "$CleanName.md"

    # 3. Copy Assets
    foreach ($file in $SourceFiles) {
        $DestFile = Join-Path $TargetFolder $file.Name
        if (-not (Test-Path $DestFile) -or $Overwrite) {
            Copy-Item -Path $file.FullName -Destination $DestFile -Force
        }
    }

    # 4. Check Overwrite
    $ForceUpdate = ($Overwrite -eq $true) -or ($Overwrite -eq 'true')
    $ShouldWrite = (-not (Test-Path $MdPath)) -or $ForceUpdate

    if (-not $ShouldWrite) { return 'SKIP' }

    # 5. Data Gathering
    $DisplayTitle = (Get-Culture).TextInfo.ToTitleCase(($CleanName -replace '-', ' ').ToLower())
    $MediaGallery = ""
    $Instructions = ""
    $Metadata = ""

    foreach ($f in $SourceFiles) {
        $Ext = $f.Extension.ToLower()

        if ($Ext -match 'jpg|jpeg|png|webp|gif|heic|tif|tiff') {
            $MediaGallery += "![image]($($f.Name))`n`n"
        }
        elseif ($Ext -match 'mp4|mov|avi|mkv') {
            $MediaGallery += "### Video Native Playback`n<video controls style={{width: '100%'}} src='./$($f.Name)' />`n`n"
        }
        elseif ($Ext -eq '.md') {
            $Instructions += (Get-Content $f.FullName -Raw) -replace '(?s)^---.*?---', ''
        }
        elseif ($Ext -eq '.txt') {
            $Instructions += "`n" + (Get-Content $f.FullName -Raw) + "`n"
        }
        elseif ($Ext -match 'json|xml|yml|yaml') {
            $Lang = $Ext.TrimStart('.')
            $RawMeta = Get-Content $f.FullName -Raw
            $Metadata += "### Metadata ($Lang)`n" + '```' + "$Lang`n$RawMeta`n" + '```' + "`n"
        }
    }

    # 6. REPLACEMENT ENGINE (Updated for Docusaurus v3 YAML safety)
    $BodyContent = if ($null -ne $Instructions -and $Instructions -ne "") { $Instructions } else { 'No instructions found.' }
    $FirstImgFile = $SourceFiles | Where-Object { $_.Extension -match 'jpg|jpeg|png|webp' } | Select-Object -First 1

    # --- PRESERVATION LOGIC ---
    # If the source file is an index, we use the raw content instead of rebuilding YAML
    if ($CleanName -eq 'index') {
        $IndexFile = $SourceFiles | Where-Object { $_.Name -eq 'index.md' } | Select-Object -First 1
        if ($null -ne $IndexFile) {
            $RawContent = Get-Content $IndexFile.FullName -Raw
            $RawContent | Set-Content -Path $MdPath -Encoding UTF8 -Force
            return 'CREATED'
        }
    }

    $YamlLines = @('---')

    # Primary fix: Use single quotes for both keys and values as requested
    $YamlLines += "'title': '$($DisplayTitle.Replace("'", "''"))'"

    # URL fix: Remove non-ASCII characters and use single quotes for slug
    $SafeSlug = $CleanName.ToLower() -replace '[^a-z0-9-]', '-' -replace '-+', '-'
    $YamlLines += "'slug': '$SafeSlug'"

    if ($null -ne $FirstImgFile) {
        $YamlLines += "'image': './$($FirstImgFile.Name)'"
        $YamlLines += "'primary_image': './$($FirstImgFile.Name)'"
    }

    $YamlLines += '---'

    # Combine YAML with the body structure
    $Tmpl = ($YamlLines -join "`r`n") + @"

# {{title}}

{{media}}

{{styled_body}}

---
{{metadata_section}}
"@

    # Apply final replacements
    $FinalMD = $Tmpl.Replace('{{title}}', $DisplayTitle)
    $FinalMD = $FinalMD.Replace('{{media}}', $MediaGallery)
    $FinalMD = $FinalMD.Replace('{{styled_body}}', $BodyContent)
    $FinalMD = $FinalMD.Replace('{{metadata_section}}', $Metadata)

    # 7. Write to File
    $FinalMD | Set-Content -Path $MdPath -Encoding UTF8 -Force

    return 'CREATED'
}

function Write-SentinelCategoryYaml {
    param($FolderPath, $FolderName, $Force)
    if (-not (Test-Path $FolderPath)) {
        New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
    }
    $Path = Join-Path $FolderPath "_category_.yml"

    $Content = @(
        "'label': '$FolderName'",
        "'link':",
        "  'type': 'generated-index'"
    ) -join "`r`n"

    $Content | Set-Content $Path -Encoding UTF8 -Force
}

function Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)

    if (-not (Test-Path $TargetRoot)) {
        New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    }

    $Path = Join-Path $TargetRoot 'index.md'
    $PrettyDate = Get-Date -Format 'MMMM dd, yyyy'
    $DirName = Split-Path $TargetRoot -Leaf
    $LowerDir = $DirName.ToLower()

    $Content = @(
        '---',
        "'id': '$LowerDir-index'",
        "'title': '$DirName'",
        "'sidebar_label': '$DirName'",
        "'sidebar_position': 1",
        "'slug': '/'",
        '---',
        '',
        "# $DirName Vault",
        "Categories: $GroupCount",
        "Last Updated: $PrettyDate"
    ) -join "`r`n"

    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}

function AutoStartWebSite {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    # 1. Administrator Privilege Check
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "--- CRITICAL: Admin privileges required ---" -ForegroundColor Red
        return
    }

    $FullSitePath = $Path.TrimEnd('\')
    $ParentPath = Split-Path $FullSitePath -Parent
    $FolderName = Split-Path $FullSitePath -Leaf

    # 2. Purge / Re-install Logic
    if (-not (Test-Path (Join-Path $FullSitePath 'package.json'))) {
        if (Test-Path $FullSitePath) {
            Remove-Item -Path $FullSitePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $ParentPath)) {
            New-Item -ItemType Directory -Path $ParentPath -Force | Out-Null
        }
        Push-Location $ParentPath
        npx --yes create-docusaurus@latest $FolderName classic --skip-install
        Pop-Location
    }

    # 3. Start Site
    if (Test-Path $FullSitePath) {
        Push-Location $FullSitePath
        if (-not (Test-Path 'node_modules')) { npm install }
        Pop-Location

        $Command = "Set-Location '$FullSitePath'; npx docusaurus start --host 0.0.0.0 --port 3000"
        Start-Process powershell.exe -ArgumentList @('-NoExit', '-Command', $Command)
    }
}