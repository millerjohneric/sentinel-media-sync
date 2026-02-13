# ==============================================================================
# Sentinel Core Library v5.1 [MDX ESCAPE FIX]
# ==============================================================================

# Global Icons for consistent UI
$Global:Icons = @{
    'Arrow'   = [char]0x2192
    'Check'   = [char]0x2714
    'Warning' = [char]0x26A0
    'Error'   = [char]0x2718
}

function Global:Build-WebPageFromTemplate {
    param($SourceFiles, $TargetFolder, $TemplateType, $Overwrite, $AssetExts)
    [int]$FilesProcessed = 0

    if (!(Test-Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
    }

    foreach ($File in $SourceFiles) {
        $Ext = $File.Extension.ToLower().TrimStart('.')

        if ($Ext -in $AssetExts) {
            # Copy images/videos/sidecars directly
            $DestAsset = Join-Path $TargetFolder $File.Name
            if (!(Test-Path $DestAsset) -or $Overwrite) {
                Copy-Item $File.FullName -Destination $DestAsset -Force
            }
        }
        elseif ($Ext -match 'md|txt|html') {
            # Process as Markdown
            $RawBase = $File.BaseName
            $WebSafeID = $RawBase -replace '\s+', '-' -replace '[^a-zA-Z0-9\-]', ''
            $MdPath = Join-Path $TargetFolder "$WebSafeID.md"

            if ((Test-Path $MdPath) -and (-not $Overwrite)) { continue }

            $RawContent = Get-Content $File.FullName -Raw
            $SafeContent = Clean-SentinelContent -Content $RawContent
            $SafeTitle = Get-SafeYamlTitle -Title $RawBase

            $FinalMD = @"
---
title: $SafeTitle
---

$SafeContent
"@
            [System.IO.File]::WriteAllText($MdPath, $FinalMD, [System.Text.Encoding]::UTF8)
            $FilesProcessed++
        }
    }
    return $FilesProcessed
}

function Global:Clear-SentinelOdometer {
    $Width = Get-SentinelWidth
    Write-Host ("`r" + (' ' * $Width) + "`r") -NoNewline
}

function Global:Clean-SentinelContent {
    param([string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return "" }

    # 1. Escape MDX sensitive characters
    $Escaped = $Content -replace '<', '&lt;' `
                        -replace '>', '&gt;' `
                        -replace '\{', '&#123;' `
                        -replace '\}', '&#125;'

    # 2. Escape colons at the start of a line to stop directive warnings
    $Escaped = $Escaped -replace '(?m)^:', '\:'

    # 3. Clean up empty markdown links []() found in your logs
    $Escaped = $Escaped -replace '\[\]\(\)', ''

    return $Escaped.Trim()
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
    if ($Role -match 'Hybrid') { return 'Red' }
    switch -regex ($Role) {
        'Photo'        { return 'Yellow' }
        'RAW'          { return 'Cyan' }
        'Video|Audio'  { return 'Magenta' }
        'Pickup'       { return 'Gray' }
        Default        { return 'White' }
    }
}

function Global:Get-SafeYamlTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return "Untitled" }

    # Escape double quotes and wrap the whole title in double quotes
    $CleanTitle = $Title -replace '"', '\"'
    return "`"$CleanTitle`""
}

function Global:Get-SentinelWebExtensions {
    param($FileTypeData)

    $FinalList = @()

    foreach ($item in $FileTypeData.WebContent) {
        if ($FileTypeData.ContainsKey($item)) {
            # It's a category (like Images), add all its extensions
            $FinalList += $FileTypeData.$item
        } else {
            # It's a direct extension (like .mp4), add it directly
            $FinalList += $item
        }
    }

    # Return unique, lowercase extensions without the dot
    return $FinalList | ForEach-Object { $_.ToLower().TrimStart('.') } | Select-Object -Unique
}

function Global:Initialize-SentinelWebRoot {
    param($RootPath)

    $AllowPurge = $script:YamlData.Settings.PurgeWebsite
    $Tmpl = $script:YamlData.Settings.TemplateDir
    $Parent = Split-Path $RootPath -Parent
    $Leaf = Split-Path $RootPath -Leaf

    # 1. FORCE WIPE
    if (Test-Path $RootPath) {
        if ($AllowPurge) {
            Write-Host "  $($Global:Icons.Warning) PurgeWebsite is TRUE. Performing Force-Wipe..." -ForegroundColor Yellow

            # Kill Node to unlock files
            Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 2

            # Completely remove the directory so npx has a 100% clean start
            Remove-Item $RootPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 2. RE-SCAFFOLD IF MISSING
    if (!(Test-Path (Join-Path $RootPath 'package.json'))) {
        Write-Host "  $($Global:Icons.Arrow) Engine missing. Scaffolding Docusaurus..." -ForegroundColor Cyan

        if (!(Test-Path $Parent)) { New-Item $Parent -ItemType Directory -Force | Out-Null }

        Push-Location $Parent
        # Use cmd /c with --yes to force the latest docusaurus scaffold
        cmd /c "npx --yes create-docusaurus@latest $Leaf classic --javascript --skip-install"
        Pop-Location

        # 3. INJECT CONFIG IMMEDIATELY
        if (Test-Path $Tmpl) {
            Write-Host "  $($Global:Icons.Check) Injecting Custom Templates..." -ForegroundColor Gray
            Copy-Item (Join-Path $Tmpl 'docusaurus.config.js') $RootPath -Force
            Copy-Item (Join-Path $Tmpl 'sidebars.js') $RootPath -Force
        }

        # 4. CLEANUP BLOAT
        $PurgeList = @('blog', 'docs', 'src/components/HomepageFeatures')
        foreach ($f in $PurgeList) {
            $p = Join-Path $RootPath $f
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }
    }

    return $true
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

function Global:Start-SentinelWebsite {
    param($Path, $Locations)

    Push-Location $Path

    if (!(Test-Path (Join-Path $Path "node_modules"))) {
        Write-Host "  $($Global:Icons.Arrow) Installing Node dependencies (First Run/After Wipe)..." -ForegroundColor Cyan
        # Using cmd /c here ensures npm is found and executed correctly
        cmd /c "npm install --quiet"
    }

    Write-Host "  $($Global:Icons.Check) Starting Docusaurus Engine..." -ForegroundColor Green

    # FIX: Use cmd /c to launch the npm batch script
    Start-Process "cmd" -ArgumentList "/c npm start" -NoNewWindow

    Pop-Location
    return "ONLINE"
}

function Global:Send-SentinelReport {
    param([string]$ReportBody, [string]$JobName = 'Sync', [string]$SiteUrl = '', [string]$WebSubFolder = '')
    Initialize-SentinelSecrets
    $Conf = $script:YamlData.'Settings'.'EmailSettings'
    if (-not $Conf.'Enabled' -or [string]::IsNullOrWhiteSpace($script:GmailUser)) { return }
    $FullLink = if (![string]::IsNullOrEmpty($WebSubFolder)) { "$($SiteUrl.TrimEnd('/'))/$($WebSubFolder.TrimStart('/'))" } else { $SiteUrl }
    try {
        $Msg = New-Object System.Net.Mail.MailMessage; $Msg.From = New-Object System.Net.Mail.MailAddress($script:GmailUser)
        $Msg.To.Add($Conf.'To'); $Msg.Subject = "Sentinel $JobName Report: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        $Msg.IsBodyHtml = $true
        $Msg.Body = "<html><body style='font-family:sans-serif;color:#333;'><h2 style='color:#2e8555;'>Sentinel $JobName Report</h2><pre style='background:#f4f4f4;padding:15px;border:1px solid #ddd;'>$ReportBody</pre>"
        if ($FullLink) { $Msg.Body += "<div style='margin-top:20px;padding:15px;background:#e8f5e9;border-left:5px solid #2e8555;'><strong>Live Site:</strong><br/><a href='$FullLink'>$FullLink</a></div>" }
        $Msg.Body += "</body></html>"
        $Smtp = New-Object System.Net.Mail.SmtpClient('smtp.gmail.com', 587); $Smtp.EnableSsl = $true
        $Smtp.Credentials = New-Object System.Net.NetworkCredential($script:GmailUser, $script:AppPassword)
        $Smtp.Send($Msg); Write-Host "[EMAIL] Report sent to $($Conf.'To')" -ForegroundColor Green
    } catch { Write-Host "[EMAIL] Failed: $($_.Exception.Message)" -ForegroundColor Red }
}

function Global:Test-SentinelExclusion {
    param([string]$Path)
    $Exclusions = $script:YamlData.'Exclusions'
    foreach ($ex in $Exclusions) {
        if ($Path -like "*\$ex\*") { return $true }
    }
    return $false
}

function Global:Write-SentinelCategoryYaml {
    param($FolderPath, $FolderName)
    if (-not (Test-Path $FolderPath)) { New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null }
    $Path = Join-Path $FolderPath "_category_.yml"
    $Content = "'label': '$FolderName'`r`n'link':`r`n  'type': 'generated-index'`r`n  'description': 'View $FolderName collection.'"
    $Content | Set-Content $Path -Encoding UTF8 -Force
}

function Global:Write-SentinelRecipeIndex {
    param([string]$TargetRoot, [int]$GroupCount)
    $Path = Join-Path $TargetRoot 'index.md'
    $DirName = Split-Path $TargetRoot -Leaf
    $Content = "---`n'title': '$DirName'`n'sidebar_label': 'Overview'`n'slug': '/'`n---`n`nimport DocCardList from '@theme/DocCardList';`n`n# $DirName Gallery`n`nTotal Collections: $GroupCount`n`n<DocCardList />"
    $Content | Set-Content -Path $Path -Encoding UTF8 -Force
}

function Global:Write-SentinelOdometer {
    param($Tag, $Source, $Path, $Current = 0, $Total = 0)

    # 1. Fix Math: Ensure percentage never exceeds 100% and handles zero totals
    $SafeTotal = if ($Total -lt $Current) { $Current } else { $Total }
    $Percent = if ($SafeTotal -gt 0) { [Math]::Min(100, [Math]::Round(($Current / $SafeTotal) * 100)) } else { 0 }

    $Width = Get-SentinelWidth
    $Prefix = "  $($Global:Icons.Arrow) [$Tag] [$Source] [$Current/$SafeTotal] ($Percent%) "

    # 2. Calculate remaining space for the path
    $RemainingSpace = $Width - $Prefix.Length - 1
    if ($RemainingSpace -lt 0) { $RemainingSpace = 0 }

    # 3. Path Shortening
    $DisplayPath = $Path
    if ($Path.Length -gt $RemainingSpace) {
        if ($RemainingSpace -gt 5) {
            $DisplayPath = "..." + $Path.Substring($Path.Length - ($RemainingSpace - 3))
        } else {
            $DisplayPath = ""
        }
    }

    # 4. THE FIX: Create a "Clear Line" string to prevent ghosting
    # This fills the rest of the console width with spaces
    $LineContent = "$Prefix$DisplayPath"
    $Padding = ""
    if ($LineContent.Length -lt $Width) {
        $Padding = " " * ($Width - $LineContent.Length - 1)
    }

    # 5. Render with Carriage Return and No New Line
    Write-Host "`r$LineContent$Padding" -NoNewline -ForegroundColor Cyan
}

function Global:Write-SentinelPhase0 {
    param(
        [Parameter(Mandatory=$true)] $Locations,
        [Parameter(Mandatory=$true)] [ValidateSet('Sync', 'Web')] $JobType
    )
    Write-Host '     STATUS      NAME                ROLE                PATH'
    foreach ($loc in $Locations) {
        $IsOnline = Test-Path $loc.Path
        $IsRelevant = if ($JobType -eq 'Web') { $loc.Role -eq 'Hybrid_Archive' } else { $loc.MonitorDepth -ge 0 }
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