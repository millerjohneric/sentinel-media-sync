# Dot-source private helper functions
Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Dot-source public commands
$PublicScripts = Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue
foreach ($Script in $PublicScripts) {
    . $Script.FullName
}

# Export public functions explicitly
Export-ModuleMember -Function $PublicScripts.BaseName