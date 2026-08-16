Set-Location -Path $PSScriptRoot

Import-Module "$PSScriptRoot\sentinel-media-sync.psd1" -Force

Invoke-SentinelArchiveSync -ConfigPath "$PSScriptRoot\Sentinel-Config.yml"
Invoke-SentinelWebPipeline -ConfigPath "$PSScriptRoot\Sentinel-Config.yml"