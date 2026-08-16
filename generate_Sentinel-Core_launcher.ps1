@'
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\Sentinel-Config.yml"
)

$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath "sentinel-media-sync.psd1"

if (Test-Path -Path $ManifestPath) {
    Import-Module -Name $ManifestPath -Force
} else {
    $PublicScripts  = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "Public\*.ps1") -ErrorAction SilentlyContinue
    $PrivateScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "Private\*.ps1") -ErrorAction SilentlyContinue
    foreach ($Script in ($PublicScripts + $PrivateScripts)) {
        . $Script.FullName
    }
}

if (-not (Test-Path -Path $ConfigPath)) {
    Write-Error "Configuration file not found at path: $ConfigPath"
    return
}

$Config = Get-SentinelConfig -Path $ConfigPath
Invoke-SentinelArchiveSync -Locations $Config.Locations -FileTypes $Config.FileTypes -Settings $Config.Settings
'@ | Set-Content -Path ".\Sentinel-Core.ps1" -Encoding UTF8