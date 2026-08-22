# --- AUTO-RUN TRIGGER ---
function Global:Invoke-RecipeOcr {
    param([string]$Source)

    if ([string]::IsNullOrWhiteSpace($Source) -or !(Test-Path $Source)) {
        Write-Host "    $($Global:Icons.Warning) OCR source invalid: $Source" -ForegroundColor Yellow
        return
    }

    $ImageFiles = Get-ChildItem -Path $Source -Recurse -File -Include *.jpg, *.jpeg, *.png
    foreach ($Img in $ImageFiles) {
        $YamlPath = [IO.Path]::ChangeExtension($Img.FullName, ".yml")
        if (Test-Path $YamlPath) {
            Write-Host "    $($Global:Icons.Check) OCR skipped (YAML exists): $($Img.Name)" -ForegroundColor Gray
            continue
        }

        # Tesseract automatically appends '.txt' to the output base filename
        $TempBase = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
        $TempTxtFile = "$TempBase.txt"
        $TessCmd = "tesseract `"$($Img.FullName)`" `"$TempBase`" -l eng"

        try {
            & $Env:COMSPEC /c $TessCmd | Out-Null
            if (Test-Path $TempTxtFile) {
                $RawText = Get-Content -Path $TempTxtFile -Raw
                Remove-Item $TempTxtFile -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "    $($Global:Icons.Error) Tesseract output file missing for $($Img.Name)" -ForegroundColor Red
                continue
            }
        } catch {
            Write-Host "    $($Global:Icons.Error) Tesseract failed on $($Img.Name): $($_.Exception.Message)" -ForegroundColor Red
            if (Test-Path $TempTxtFile) { Remove-Item $TempTxtFile -Force -ErrorAction SilentlyContinue }
            continue
        }

        # Parse key/value pairs into dictionary
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
            $YamlContent | Set-Content -Path $YamlPath -Encoding UTF8
            Write-Host "    $($Global:Icons.Check) OCR generated: $([IO.Path]::GetFileName($YamlPath))" -ForegroundColor Gray
        } else {
            Write-Host "    $($Global:Icons.Warning) OCR produced no parsable key/value for $($Img.Name)" -ForegroundColor Yellow
        }
    }
}