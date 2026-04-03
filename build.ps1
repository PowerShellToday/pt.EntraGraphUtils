#Requires -Version 7.0
param(
    [string]$Version = '0.1.0',
    [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleName = Split-Path $PSScriptRoot -Leaf
$DistPath = Join-Path $PSScriptRoot "dist/$ModuleName"
$EnUsPath = Join-Path $DistPath 'en-US'

Write-Host "Building $ModuleName v$Version..." -ForegroundColor Cyan

# --- Clean output ---
if (Test-Path $DistPath) { Remove-Item $DistPath -Recurse -Force }
New-Item -ItemType Directory -Path $EnUsPath -Force | Out-Null

# --- Gather sources ---
$PrivateFiles = Get-ChildItem "$PSScriptRoot/src/private" -Filter *.ps1 | Sort-Object Name
$PublicFiles  = Get-ChildItem "$PSScriptRoot/src/public"  -Filter *.ps1 | Sort-Object Name
$projectUri   = (Import-PowerShellDataFile (Join-Path $PSScriptRoot "src/$ModuleName.psd1")).PrivateData.PSData.ProjectUri

# --- Concatenate into single .psm1 ---
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine("# .ExternalHelp $ModuleName-help.xml")
[void]$sb.AppendLine()
[void]$sb.AppendLine('#region Private Functions')
foreach ($f in $PrivateFiles) {
    [void]$sb.AppendLine("#region $($f.BaseName)")
    [void]$sb.AppendLine((Get-Content $f.FullName -Raw).TrimEnd())
    [void]$sb.AppendLine("#endregion $($f.BaseName)")
    [void]$sb.AppendLine()
}
[void]$sb.AppendLine('#endregion Private Functions')
[void]$sb.AppendLine()

[void]$sb.AppendLine('#region Public Functions')
foreach ($f in $PublicFiles) {
    $helpUri = "$projectUri/blob/main/docs/$($f.BaseName).md"
    $content = (Get-Content $f.FullName -Raw).TrimEnd()
    if ($content -notmatch 'HelpUri') {
        if ($content -match '\[CmdletBinding\(\)\]') {
            $content = $content -replace '\[CmdletBinding\(\)\]', "[CmdletBinding(HelpUri = '$helpUri')]"
        } else {
            $content = $content -replace '\[CmdletBinding\(([^)]+)\)\]', "[CmdletBinding(`$1, HelpUri = '$helpUri')]"
        }
    }
    [void]$sb.AppendLine("#region $($f.BaseName)")
    [void]$sb.AppendLine($content)
    [void]$sb.AppendLine("#endregion $($f.BaseName)")
    [void]$sb.AppendLine()
}
[void]$sb.AppendLine('#endregion Public Functions')
[void]$sb.AppendLine()

$exportList = ($PublicFiles | Select-Object -ExpandProperty BaseName) -join "', '"
[void]$sb.AppendLine("Export-ModuleMember -Function @('$exportList')")

$psm1Path = Join-Path $DistPath "$ModuleName.psm1"
$sb.ToString() | Set-Content $psm1Path -Encoding UTF8

# --- Copy + patch manifest ---
$srcPsd1 = Join-Path $PSScriptRoot "src/$ModuleName.psd1"
$destPsd1 = Join-Path $DistPath     "$ModuleName.psd1"
$versionParts    = $Version -split '-', 2
$semVer          = $versionParts[0]
$prereleaseLabel = if ($versionParts.Count -gt 1) { $versionParts[1] } else { '' }

$exportArray = ($PublicFiles | Select-Object -ExpandProperty BaseName | ForEach-Object { "        '$_'" }) -join "`n"
$psd1Content = Get-Content $srcPsd1 -Raw
$psd1Content = $psd1Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion     = '$semVer'"
$psd1Content = $psd1Content -replace "Prerelease\s*=\s*'[^']*'", "Prerelease   = '$prereleaseLabel'"
$psd1Content = $psd1Content -replace '(?s)FunctionsToExport\s*=\s*@\([^)]*\)', "FunctionsToExport = @(`n$exportArray`n    )"
$psd1Content | Set-Content $destPsd1 -Encoding UTF8

Write-Host "  Compiled: $psm1Path"
Write-Host "  Manifest: $destPsd1"

# --- Sync docs and build MAML help ---
if (Get-Module -Name PlatyPS -ListAvailable) {
    Import-Module PlatyPS -Force
    $docsPath = Join-Path $PSScriptRoot 'docs'

    # Import dev module so PlatyPS can reflect on it
    Import-Module (Join-Path $PSScriptRoot "src/$ModuleName.psd1") -Force

    # Generate .md for any new public functions
    foreach ($f in $PublicFiles) {
        $mdPath = Join-Path $docsPath "$($f.BaseName).md"
        if (-not (Test-Path $mdPath)) {
            New-MarkdownHelp -Command $f.BaseName -OutputFolder $docsPath | Out-Null
            Write-Host "  Docs generated: $($f.BaseName).md" -ForegroundColor Gray
        }
    }

    # Refresh all existing .md files from comment-based help
    Update-MarkdownHelp -Path $docsPath | Out-Null
    Write-Host "  Docs updated: $docsPath" -ForegroundColor Gray

    # Patch online version URLs
    Get-ChildItem $docsPath -Filter *.md |
        Where-Object { $_.Name -notlike 'about_*' -and $_.Name -ne 'README.md' } |
        ForEach-Object {
            $url        = "$projectUri/blob/main/docs/$($_.Name)"
            $mdContent  = Get-Content $_.FullName -Raw
            $updated    = $mdContent -replace '(?m)^online version:.*$', "online version: $url"
            if ($updated -ne $mdContent) {
                $updated | Set-Content $_.FullName -Encoding UTF8 -NoNewline
            }
        }

    # Remove orphaned .md files
    $currentFunctions = $PublicFiles.BaseName
    Get-ChildItem $docsPath -Filter *.md |
        Where-Object { $_.Name -notlike 'about_*' -and $_.Name -ne 'README.md' -and $_.BaseName -notin $currentFunctions } |
        ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Host "  Docs removed (orphan): $($_.Name)" -ForegroundColor Yellow
        }

    # Compile MAML
    New-ExternalHelp -Path $docsPath -OutputPath $EnUsPath -Force | Out-Null
    Write-Host "  MAML help: $EnUsPath" -ForegroundColor Green
}
else {
    Write-Warning "PlatyPS not found — docs and MAML help skipped. Install with: Install-Module PlatyPS"
}

$aboutSources = Get-ChildItem (Join-Path $PSScriptRoot 'docs') -Filter 'about_*.help.txt' -ErrorAction SilentlyContinue
if ($aboutSources) {
    foreach ($aboutSource in $aboutSources) {
        $aboutDest = Join-Path $EnUsPath $aboutSource.Name
        Copy-Item -Path $aboutSource.FullName -Destination $aboutDest -Force
        Write-Host "  About help: $aboutDest" -ForegroundColor Green
    }
}
else {
    Write-Warning "No about_*.help.txt files found in docs/ — about help skipped."
}

Write-Host "Build complete: $DistPath" -ForegroundColor Green

# --- Optional: run Pester against compiled output ---
if ($Test) {
    $env:MYMODULE_PATH = $DistPath
    Write-Host "`nRunning tests against compiled output ($DistPath)..." -ForegroundColor Cyan

    $cfg = New-PesterConfiguration
    $cfg.Run.Path = Join-Path $PSScriptRoot 'tests'
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Detailed'
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputPath = Join-Path $PSScriptRoot 'testResults-compiled.xml'

    $result = Invoke-Pester -Configuration $cfg
    if ($result.FailedCount -gt 0) {
        throw "$($result.FailedCount) test(s) failed."
    }
}
