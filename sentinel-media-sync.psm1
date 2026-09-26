# Load all private helper functions
Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        . $_.FullName
    } catch {
        Write-Warning "Failed to load script: $($_.Name). Details: $_"
    }
}

# Dot-source public commands
$ExistingFunctions = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

$PublicScripts = Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue
foreach ($Script in $PublicScripts) {
    try {
        . $Script.FullName
    } catch {
        Write-Warning "Failed to load script: $($Script.Name). Details: $_"
    }
}

# Automatically capture and export any newly introduced functions
$NewFunctions = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue | Where-Object { $ExistingFunctions -notcontains $_.Name } | Select-Object -ExpandProperty Name)

if ($NewFunctions) {
    Export-ModuleMember -Function $NewFunctions
}