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
            $script:GmailCred = $TempCred
            Write-Host "[SECURITY] Credentials loaded from $SecretFile" -ForegroundColor Green
        }
        catch {
            Write-Host "[SECURITY] Failed to load credentials from $SecretFile" -ForegroundColor Yellow
        }
    }
}
