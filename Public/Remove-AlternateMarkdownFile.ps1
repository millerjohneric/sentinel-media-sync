function Remove-AlternateMarkdownFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $extension = [System.IO.Path]::GetExtension($TargetPath)
    
    if ($extension -eq '.md') {
        $altPath = [System.IO.Path]::ChangeExtension($TargetPath, '.mdx')
        if (Test-Path -Path $altPath) {
            Remove-Item -Path $altPath -Force
        }
    } elseif ($extension -eq '.mdx') {
        $altPath = [System.IO.Path]::ChangeExtension($TargetPath, '.md')
        if (Test-Path -Path $altPath) {
            Remove-Item -Path $altPath -Force
        }
    }
}