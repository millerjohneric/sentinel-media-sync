$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Path = Join-Path $ProjectRoot "Sentinel-Core.ps1"
$content = Get-Content $Path -Raw
$tokens = $null
$errors = $null

$ast = [System.Management.Automation.Language.Parser]::ParseInput(
    $content,
    [ref]$tokens,
    [ref]$errors
)

$functions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $false)

$sorted = $functions | Sort-Object Name

$newContent = $content

foreach ($func in $sorted) {
    $newContent += "`n`n" + $func.Extent.Text
}

Set-Content $Path $newContent
