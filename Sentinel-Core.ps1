# ==============================================================================
# Sentinel Core Library v3.0 (Strict Credential Sanitizer)
# ==============================================================================

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
    param($Locations)
    Write-Host '     STATUS      NAME                ROLE                PATH'
    foreach ($loc in $Locations) {
        $IsOnline = Test-Path $loc.Path

        # GEEK FIX: If 'Enabled' isn't in YAML, assume True.
        # But if it's a Hybrid_Archive, we mark it as [READY]
        $StatusStr = if (-not $IsOnline) { '[OFFLINE ]' }
                     elseif ($loc.Role -eq 'Hybrid_Archive') { '[READY   ]' }
                     else { '[SKIP    ]' }

        $Name = "[$($loc.Name.PadRight(15))]"
        $Role = "[$($loc.Role.PadRight(18))]"
        $Path = $loc.Path

        Write-Host "     $StatusStr  $Name $Role $Path"
    }
}

function Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current = 0, $Total = 0)
    $SafeWidth = Get-SentinelWidth
    $F_Curr = Format-SentinelNum $Current
    $F_Tot = Format-SentinelNum $Total
    $Progress = ""
    if ($Total -gt 0) { $Progress = "[$($F_Curr.PadLeft($F_Tot.Length))/$F_Tot]" }

    $MaxPath = $SafeWidth - 65
    $CleanPath = $Path
    if ($Path.Length -gt $MaxPath -and $MaxPath -gt 5) {
        $CutPoint = $Path.Length - ($MaxPath - 3)
        if ($CutPoint -gt 0) { $CleanPath = '...' + $Path.Substring($CutPoint) }
    }

    $Line = "`r  >> [{0,-8}] [{1,-12}] {2,-15} {3}" -f $Tag, $Source, $Progress, $CleanPath
    Write-Host $Line.PadRight($SafeWidth) -NoNewline -ForegroundColor Gray
}

function Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}

# --- SECURITY & CREDENTIALS ---

function Initialize-SentinelSecrets {
    $Conf = $script:YamlData.'Settings'.'EmailSettings'
    $BaseDir = 'H:\sentinel-media-sync'
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
        [string]$JobName = 'Sync'
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
        $Msg.Body = $ReportBody

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
            Remove-Item (Join-Path 'H:\sentinel-media-sync' $Conf.'CredPath') -Force -ErrorAction SilentlyContinue
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

function Build-WebPageFromTemplate {
    param(
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$SourceFile,

        [Parameter(Mandatory=$true)]
        [string]$TargetFolder,

        [Parameter(Mandatory=$true)]
        [string]$TemplateType,

        [Parameter(Mandatory=$true)]
        [bool]$Overwrite
    )

    # Ensure the destination exists
    if (-not (Test-Path $TargetFolder)) { New-Item $TargetFolder -ItemType Directory -Force | Out-Null }

    $TargetFileName = $SourceFile.BaseName + '.md'
    $TargetPath = Join-Path $TargetFolder $TargetFileName

    # Skip logic
    if ((Test-Path $TargetPath) -and (-not $Overwrite)) {
        return 'SKIPPED'
    }

    try {
        # Using your updated absolute path from YAML
        $TemplateDir = $script:YamlData.'Settings'.'TemplateDir'

        # Ensure we are looking for a .md file
        $CleanTemplate = if ($TemplateType -match '\.md$') { $TemplateType } else { "$TemplateType.md" }
        $TemplatePath = Join-Path $TemplateDir $CleanTemplate

        if (-not (Test-Path $TemplatePath)) {
            return 'ERROR'
        }

        # Read the recipe-card.md
        $TemplateContent = Get-Content $TemplatePath -Raw

        # Perform replacements
        $Output = $TemplateContent.Replace('{{title}}', ($SourceFile.BaseName -replace '-', ' '))
        $Output = $Output.Replace('{{slug}}', $SourceFile.BaseName.ToLower())
        $Output = $Output.Replace('{{primary_image}}', "![[$($SourceFile.Name)]]")

        # Write out the new markdown file
        $Output.Trim() | Set-Content -Path $TargetPath -Force -Encoding UTF8

        return 'CREATED'
    }
    catch {
        return 'ERROR'
    }
}

function AutoStartWebSite {
    param(
        [string]$Path
    )

    # Force UTF8 for this session to fix the ðŸš€ icon issues
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    Write-Host "`n🚀 Preparing to launch Docusaurus..." -ForegroundColor Cyan

    if (Test-Path $Path) {
        Write-Host "🏠 Site Root: $Path" -ForegroundColor Gray
        Write-Host "🦖 Spawning Development Server in a NEW window..." -ForegroundColor Green

        # We launch a separate PowerShell window for the server
        # -NoExit keeps the window open if there is an error
        # -Command runs the location change and the start command
        $ArgList = "-NoExit", "-Command", "Set-Location '$Path'; npx docusaurus start --host 0.0.0.0 --port 3000"

        Start-Process powershell.exe -ArgumentList $ArgList

        Write-Host "💡 Access locally at http://localhost:3000" -ForegroundColor Yellow
        Write-Host "✅ Mission complete. This window will now close." -ForegroundColor Gray
    }
    else {
        Write-Host "❌ Error: Cannot find $Path" -ForegroundColor Red
    }
}