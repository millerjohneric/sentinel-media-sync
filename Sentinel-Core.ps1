# ==============================================================================
# Sentinel Core Library v3.0 (Strict Credential Sanitizer)
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
#$OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
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

        # Determine Status and its Color
        if (-not $IsOnline) {
            $StatusStr = '[OFFLINE ]'
            $StatusColor = 'Red'
        }
        elseif ($loc.Role -eq 'Hybrid_Archive') {
            $StatusStr = '[READY   ]'
            $StatusColor = 'Green'
        }
        else {
            $StatusStr = '[SKIP    ]'
            $StatusColor = 'DarkGray'
        }

        $Name = "[$($loc.Name.PadRight(15))]"
        $Role = "[$($loc.Role.PadRight(18))]"
        $Path = $loc.Path

        # Get the Role Color from your helper
        $RoleColor = Get-SentinelRoleColor -Role $loc.Role

        # Write the line in colored chunks
        Write-Host "     " -NoNewline
        Write-Host $StatusStr -NoNewline -ForegroundColor $StatusColor
        Write-Host "  $Name " -NoNewline
        Write-Host $Role -NoNewline -ForegroundColor $RoleColor
        Write-Host " $Path"
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

function Write-SentinelCategoryYaml {
    param(
        [string]$FolderPath,
        [string]$FolderName,
        [bool]$Force = $false
    )

    $CategoryFile = Join-Path $FolderPath '_category_.yml'

    # Fix: Wrap Test-Path in parentheses so -and parses correctly
    if ((Test-Path $CategoryFile) -and (-not $Force)) { return }

    $TextInfo = (Get-Culture).TextInfo
    $CleanLabel = $TextInfo.ToTitleCase($FolderName.Replace('-', ' ').Replace('_', ' '))

    # SCHEMA FIX: 'title' is nested under 'link' using single quotes
    $YamlContent = @"
label: '$CleanLabel'
link:
  type: 'generated-index'
  title: '$CleanLabel Recipes'
  description: 'A collection of our favorite $FolderName recipes.'
"@

    $YamlContent | Set-Content -Path $CategoryFile -Force -Encoding UTF8
}


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
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$SourceFile,

        [Parameter(Mandatory=$true)]
        [string]$TargetFolder,

        [Parameter(Mandatory=$true)]
        [string]$TemplateType,

        [Parameter(Mandatory=$true)]
        [bool]$Overwrite
    )
    $Output | Set-Content -Path $TargetFile -Force -Encoding UTF8
    if (-not (Test-Path $TargetFolder)) { New-Item $TargetFolder -ItemType Directory -Force | Out-Null }

    $TargetFileName = $SourceFile.BaseName + '.md'
    $TargetPath = Join-Path $TargetFolder $TargetFileName

    if ((Test-Path $TargetPath) -and (-not $Overwrite)) { return 'SKIPPED' }

    try {
        $YamlPath = Join-Path $SourceFile.DirectoryName ($SourceFile.BaseName + '.yml')
        $Data = if (Test-Path $YamlPath) { Get-Content $YamlPath -Raw | ConvertFrom-Yaml } else { $null }

        $TemplateDir = $script:YamlData.'Settings'.'TemplateDir'
        $TemplatePath = Join-Path $TemplateDir "$TemplateType.md"
        if (-not (Test-Path $TemplatePath)) { return 'ERROR' }
        $TemplateContent = Get-Content $TemplatePath -Raw

        $ImgExts = $script:YamlData.'FileTypes'.'Images'
        $DocExts = $script:YamlData.'FileTypes'.'Docs'

        $PrimaryDisplay = if ($SourceFile.Extension -in $ImgExts) {
            "![Finished Dish]($($SourceFile.Name))"
        } elseif ($SourceFile.Extension -in $DocExts) {
            "### 📄 Attached Document`n[Download/View $($SourceFile.Name)]($($SourceFile.Name))"
        } else {
            "File: $($SourceFile.Name)"
        }

        $DisplayTitle = if ($Data.'title') { $Data.'title' } else { ($SourceFile.BaseName -replace '-', ' ') }
        $LowSlug = $SourceFile.BaseName.ToLower()

        $IngList = if ($Data.'ingredients') { ($Data.'ingredients' | ForEach-Object { "* $_" }) -join "`n" } else { "* No ingredients listed" }
        $i = 1
        $StepList = if ($Data.'instructions') { ($Data.'instructions' | ForEach-Object { "$($i++). $_" }) -join "`n" } else { "1. Refer to source file." }

        # GEEK FIX: Handle conditional logic BEFORE the .Replace() method
        $ServingsText = if ($Data.'servings') { $Data.'servings' } else { 'Varies' }

        # --- PHASE 3: REPLACEMENT ENGINE ---
        $Output = $TemplateContent

        # Values are wrapped in single quotes here
        $Output = $Output.Replace("{{title}}", "'$DisplayTitle'")
        $Output = $Output.Replace("{{slug}}", "'$LowSlug'")
        $Output = $Output.Replace("{{image_path}}", "'$($SourceFile.Name)'")
        $Output = $Output.Replace("{{xmp_path}}", "'$($SourceFile.BaseName).yml'")
        $Output = $Output.Replace("{{servings}}", "'$ServingsText'")

        # Body content (No quotes needed)
        $Output = $Output.Replace("{{primary_image}}", $PrimaryDisplay)
        $Output = $Output.Replace("{{ingredients_list}}", $IngList)
        $Output = $Output.Replace("{{instructions_list}}", $StepList)

        $FinalContent = $Output.Trim()
        $FinalContent | Set-Content -Path $TargetPath -Force -Encoding UTF8
        return 'CREATED'
    }
    catch {
        Write-Host "  !! Error on $($SourceFile.Name): $($_.Exception.Message)" -ForegroundColor Red
        return 'ERROR'
    }
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

        # Use -EncodedCommand or -Command with explicit UTF8 settings for the child process
        $Command = "chcp 65001 > `$null; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Set-Location '$Path'; npx docusaurus start --host 0.0.0.0 --port 3000"

        $ArgList = @("-NoExit", "-Command", $Command)

        Start-Process powershell.exe -ArgumentList $ArgList

        Write-Host "💡 Access locally at http://localhost:3000" -ForegroundColor Gray
    } else {
        Write-Host "⚠️  Launch Failed: Path not found -> $Path" -ForegroundColor Red
    }
}