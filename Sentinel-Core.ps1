# ==============================================================================
# Sentinel Core Library v3.0 (PS 5.1 Hardened)
# ==============================================================================
# Top of Sentinel-Core.ps1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$Global:Icons = @{
    Arrow    = [char]0x2192 # →
    Broom    = [char]0x232B # ⌫
    Check    = [char]0x221A # √
}

# Update Write-SentinelOdometer to use the Global Icons
function Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current = 0, $Total = 0)

    # Calculate progress
    $Percent = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100) } else { 0 }

    Write-Host "  $($Global:Icons.Arrow) " -NoNewline -ForegroundColor Gray
    Write-Host "[$Tag] " -NoNewline -ForegroundColor Cyan
    Write-Host "[$Source] " -NoNewline -ForegroundColor Gray
    Write-Host "[$Current/$Total] " -NoNewline -ForegroundColor White
    Write-Host " $Path" -ForegroundColor Gray
}

# --- FORMATTING & UI HELPERS ---

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
        Write-Host " [$($loc.Role.PadRight(18))] " -ForegroundColor $RoleColor -NoNewline
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

    # 2. Extract Primary Info (LastIndexOf preserves 'natural-body-wash')
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

    # 4. Check Overwrite (Strict Boolean for PS 5.1)
    $ShouldWrite = (-not (Test-Path $MdPath)) -or ($Overwrite -eq $true)
    if (-not $ShouldWrite) { return 'SKIP' }

    # 5. Data Gathering
    $DisplayTitle = (Get-Culture).TextInfo.ToTitleCase(($CleanName -replace '-', ' ').ToLower())
    $MediaGallery = ""
    $Instructions = ""
    $Metadata = ""

    foreach ($f in $SourceFiles) {
        $Ext = $f.Extension.ToLower()

        # Images & Videos
        if ($Ext -match 'jpg|jpeg|png|webp|gif|heic|tif|tiff') {
            $MediaGallery += "![image]($($f.Name))`n`n"
        }
        elseif ($Ext -match 'mp4|mov|avi|mkv') {
            $MediaGallery += "### Video Native Playback`n<video controls style={{width: '100%'}} src='./$($f.Name)' />`n`n"
        }
        # Instructions (Web/Docs)
        elseif ($Ext -eq '.md') {
            $Instructions += (Get-Content $f.FullName -Raw) -replace '(?s)^---.*?---', ''
        }
        elseif ($Ext -eq '.txt') {
            $Instructions += "`n" + (Get-Content $f.FullName -Raw) + "`n"
        }
        # Metadata (Sidecars)
        elseif ($Ext -match 'json|xml|yml|yaml') {
            $Lang = $Ext.TrimStart('.')
            $RawMeta = Get-Content $f.FullName -Raw
            $Metadata += "### Metadata ($Lang)`n" + '```' + "$Lang`n$RawMeta`n" + '```' + "`n"
        }
    }

    # 6. REPLACEMENT ENGINE (Variable Based)
    $FinalInstructions = "No instructions found."
    if ($Instructions.Trim()) { $FinalInstructions = $Instructions }

    $Tmpl = @(
        "---",
        "title: {{title}}",
        "slug: {{slug}}",
        "---",
        "",
        "# {{title}}",
        "",
        "{{primary_image}}",
        "",
        "## Instructions",
        "{{instructions_list}}",
        "",
        "---",
        "{{metadata_section}}"
    ) -join "`r`n"

    $FinalMD = $Tmpl
    $FinalMD = $FinalMD.Replace('{{title}}', $DisplayTitle)
    $FinalMD = $FinalMD.Replace('{{slug}}', $CleanName.ToLower())
    $FinalMD = $FinalMD.Replace('{{primary_image}}', $MediaGallery)
    $FinalMD = $FinalMD.Replace('{{instructions_list}}', $FinalInstructions)
    $FinalMD = $FinalMD.Replace('{{metadata_section}}', $Metadata)

    # 7. Write to NAS (Hardened)
    $FinalMD | Set-Content -Path $MdPath -Encoding UTF8 -Force

    return 'CREATED'
}

function Write-SentinelCategoryYaml {
    param($FolderPath, $FolderName, $Force)
    if (-not (Test-Path $FolderPath)) { New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null }
    $Path = Join-Path $FolderPath "_category_.yml"
    "label: '$FolderName'`nlink:`n  type: generated-index" | Set-Content $Path -Encoding UTF8 -Force
}

function Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot "index.md"
    $PrettyDate = Get-Date -Format "MMMM dd, yyyy"
    $Content = @(
        "---",
        "title: Recipe Library",
        "sidebar_position: 1",
        "slug: /recipes",
        "---",
        "",
        "# Recipe Vault",
        "Categories: $GroupCount",
        "Last Updated: $PrettyDate"
    ) -join "`r`n"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}



function AutoStartWebSite {
    param(
        [string]$Path
    )

    # GEEK FIX: Force the internal PyCharm stream to accept UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#    $OutputEncoding = [System.Text.Encoding]::UTF8

    # This specifically targets the PyCharm console buffer
    if ($Host.Name -match 'JetBrains') {
        $ExecutionContext.InvokeCommand.GetCommand('Set-Variable', 'Cmdlet').Invoke()
    }

    Write-Host "`n🚀 Preparing to launch Docusaurus..." -ForegroundColor Cyan

    if (Test-Path $Path) {
        Write-Host "🏠 Site Root: $Path" -ForegroundColor Gray
        Write-Host "🦖 Spawning Development Server in a NEW window..." -ForegroundColor Green
        if ($true){
            # Use -EncodedCommand or -Command with explicit UTF8 settings for the child process
            $Command = "chcp 65001 > `$null; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Set-Location '$Path'; npx docusaurus start --host 0.0.0.0 --port 3000"

            $ArgList = @("-NoExit", "-Command", $Command)

            Start-Process powershell.exe -ArgumentList $ArgList

        } else {
            Set-Location $Path
            npx docusaurus start --host 0.0.0.0 --port 3000
            Write-Host "💡 Access locally at http://localhost:3000" -ForegroundColor Gray
        }

    } else {
        Write-Host "⚠️  Launch Failed: Path not found -> $Path" -ForegroundColor Red
    }
}

if ($false) {

    Write-Host "`n  [LAUNCH] Spawning Docusaurus..." -ForegroundColor Green
    $TargetSitePath = 'H:\MakeMeASammich\website'
    AutoStartWebSite -Path $TargetSitePath

}