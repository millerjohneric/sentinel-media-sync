# Load all private and public helper functions
$ScriptFiles = Get-ChildItem -Path $PSScriptRoot -Include '*.ps1' -Recurse
foreach ($File in $ScriptFiles) {
    try {
        . $File.FullName
    } catch {
        Write-Error "Failed to load script: $($File.Name). Details: $_"
    }
}
# Dot-source private helper functions
Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Dot-source public commands and track what functions get added to the session
$ExistingFunctions = @(Get-Command -Module $MyInvocation.MyName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

$PublicScripts = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($Script in $PublicScripts) {
    . $Script.FullName
}

# Automatically capture and export any newly introduced functions from the Public folder
$NewFunctions = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue | Where-Object { $ExistingFunctions -notcontains $_.Name } | Select-Object -ExpandProperty Name)

if ($NewFunctions) {
    Export-ModuleMember -Function $NewFunctions
}