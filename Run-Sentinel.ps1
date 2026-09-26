[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Import the module from the same directory
$ModulePath = Join-Path $PSScriptRoot 'sentinel-media-sync.psd1'
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
} else {
    Write-Error "CRITICAL: Module manifest not found at '$ModulePath'."
    exit 1
}

# Run the Sentinel sync
Start-SentinelSync














