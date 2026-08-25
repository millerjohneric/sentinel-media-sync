function Start-SentinelSync {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    process {
        $ErrorActionPreference = 'Stop'

        if (-not $ConfigPath -or -not (Test-Path -Path $ConfigPath)) {
            $ConfigPath = "C:\Source\GEEK\Sentinel\Sentinel-Config.yml"
        }

        if (-not (Test-Path -Path $ConfigPath)) {
            Write-Error "CRITICAL: Config file not found at '$ConfigPath'."
            return
        }

        Write-Host "Running Sentinel Sync using config: $ConfigPath" -ForegroundColor Cyan

        if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
            Write-Error "ConvertFrom-Yaml cmdlet not found. Ensure powershell-yaml module is installed."
            return
        }

        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml

        # Package Sentinel Suite for transport (if enabled in config)
        if ($Config.Settings.EnableTransportBackup -eq $true) {
            $BackupZip = "$env:USERPROFILE\Desktop\Sentinel_v9.1_Backup.zip"
            Write-Host "`nPacking Sentinel Suite for transport..." -ForegroundColor Cyan
            if (Test-Path "$PSScriptRoot\..") {
                Compress-Archive -Path "$PSScriptRoot\.." -DestinationPath $BackupZip -Force -ErrorAction SilentlyContinue
                Write-Host "MISSION PACKED: Check your Desktop for Sentinel_v9.1_Backup.zip" -ForegroundColor Green
            }
        }

        # Register Scheduled Task using the master runner script
        $TaskName = "SentinelMediaSync"
        $ScriptTarget = "C:\Source\GEEK\Sentinel\sentinel-media-sync\Run-Sentinel.ps1"
        
        $Action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptTarget`""
        $Trigger = New-ScheduledTaskTrigger -Daily -At 12:00AM

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            try {
                Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $TaskName -Description 'Daily synchronization for The Source media archives.' -Force -ErrorAction Stop | Out-Null
                Write-Host "MISSION SUCCESSFUL" -ForegroundColor Green
                Write-Host "Task '$TaskName' registered successfully." -ForegroundColor Cyan
            }
            catch {
                Write-Host "WARNING: Could not auto-register scheduled task. Details: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "NOTICE: Scheduled task registration skipped (Administrator privileges required)." -ForegroundColor Yellow
        }
    }
}