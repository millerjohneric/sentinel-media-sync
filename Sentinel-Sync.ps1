[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Sentinel-Config.yml')
)

Set-Location -Path $PSScriptRoot

$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'sentinel-media-sync.psd1'

if (Test-Path -Path $ManifestPath) {
    Import-Module -Name $ManifestPath -Force
} else {
    $PublicScripts  = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public\*.ps1') -ErrorAction SilentlyContinue
    $PrivateScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private\*.ps1') -ErrorAction SilentlyContinue
    foreach ($Script in ($PublicScripts + $PrivateScripts)) {
        . $Script.FullName
    }
}

if (-not (Test-Path -Path $ConfigPath)) {
    Write-Error "Configuration file not found at path: $ConfigPath"
    return
}

if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    Write-Error "ConvertFrom-Yaml cmdlet not found. Ensure powershell-yaml module is installed."
    return
}

$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Yaml

Invoke-SentinelArchiveSync -Locations $Config.Locations -FileTypes $Config.FileTypes -Settings $Config.Settings
