function Invoke-SentinelRecipeOcr {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path -Path $Source)) {
        Write-Host "    $($Global:Icons.Warning) OCR source invalid: $Source" -ForegroundColor Yellow
        return
    }

    $ImageFiles = Get-ChildItem -Path $Source -Recurse -File -Include *.jpg, *.jpeg, *.png
    foreach ($Img in $ImageFiles) {
        $YamlPath = [System.IO.Path]::ChangeExtension($Img.FullName, ".yml")
        if (Test-Path -Path $YamlPath) {
            Write-Host "    $($Global:Icons.Check) OCR skipped (YAML exists): $($Img.Name)" -ForegroundColor Gray
            continue
        }

        $TempTxt = [System.IO.Path]::GetTempFileName()
        $TessCmd = "tesseract `"$($Img.FullName)`" `"$TempTxt`" -l eng"
        try {
            & $Env:COMSPEC /c $TessCmd | Out-Null
        } catch {
            Write-Host "    $($Global:Icons.Error) Tesseract failed on $($Img.Name): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $RawText = Get-Content -Path $TempTxt -Raw
        Remove-Item -Path $TempTxt -Force

        $YamlObj = @{}
        foreach ($Line in $RawText -split "`n") {
            $trim = $Line.Trim()
            if ($trim -match '^([^:]+):\s*(.+)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                $YamlObj[$key] = $val
            }
        }

        if ($YamlObj.Count -gt 0) {
            $YamlContent = $YamlObj | ConvertTo-Yaml
            [System.IO.File]::WriteAllText($YamlPath, $YamlContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "    $($Global:Icons.Check) OCR generated: $([System.IO.Path]::GetFileName($YamlPath))" -ForegroundColor Gray
        } else {
            Write-Host "    $($Global:Icons.Warning) OCR produced no parsable key/value for $($Img.Name)" -ForegroundColor Yellow
        }
    }
}