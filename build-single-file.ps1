#Requires -Version 7.0
<#
.SYNOPSIS
    Standalone build variant — compiles the module into a single .psm1 without running tests.
.PARAMETER Version
    Semantic version to stamp into the manifest. Default: 0.1.0
#>
param(
    [string]$Version = '0.1.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleName = Split-Path $PSScriptRoot -Leaf
$DistPath = Join-Path $PSScriptRoot "dist/$ModuleName"
$EnUsPath = Join-Path $DistPath 'en-US'

Write-Host "Building $ModuleName v$Version (single-file)..." -ForegroundColor Cyan

if (Test-Path $DistPath) { Remove-Item $DistPath -Recurse -Force }
New-Item -ItemType Directory -Path $EnUsPath -Force | Out-Null

$PrivateFiles = Get-ChildItem "$PSScriptRoot/src/private" -Filter *.ps1 | Sort-Object Name
$PublicFiles  = Get-ChildItem "$PSScriptRoot/src/public"  -Filter *.ps1 | Sort-Object Name
$projectUri   = (Import-PowerShellDataFile (Join-Path $PSScriptRoot "src/$ModuleName.psd1")).PrivateData.PSData.ProjectUri

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
    $content  = (Get-Content $f.FullName -Raw).TrimEnd()
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

$sb.ToString() | Set-Content (Join-Path $DistPath "$ModuleName.psm1") -Encoding UTF8

$versionParts    = $Version -split '-', 2
$semVer          = $versionParts[0]
$prereleaseLabel = if ($versionParts.Count -gt 1) { $versionParts[1] } else { '' }

$exportArray = ($PublicFiles | Select-Object -ExpandProperty BaseName | ForEach-Object { "        '$_'" }) -join "`n"
$psd1Content = Get-Content (Join-Path $PSScriptRoot "src/$ModuleName.psd1") -Raw
$psd1Content = $psd1Content -replace "ModuleVersion\s*=\s*'[^']*'", "ModuleVersion     = '$semVer'"
$psd1Content = $psd1Content -replace "Prerelease\s*=\s*'[^']*'", "Prerelease   = '$prereleaseLabel'"
$psd1Content = $psd1Content -replace '(?s)FunctionsToExport\s*=\s*@\([^)]*\)', "FunctionsToExport = @(`n$exportArray`n    )"
$psd1Content | Set-Content (Join-Path $DistPath "$ModuleName.psd1") -Encoding UTF8

if (Get-Module -Name PlatyPS -ListAvailable) {
    Import-Module PlatyPS -Force
    New-ExternalHelp -Path (Join-Path $PSScriptRoot 'docs') -OutputPath $EnUsPath -Force | Out-Null
    Write-Host "  MAML help: $EnUsPath" -ForegroundColor Green
}
else {
    Write-Warning "PlatyPS not found — MAML help skipped. Install with: Install-Module PlatyPS"
}

$aboutHelpSource = Join-Path $PSScriptRoot "docs/about_$ModuleName.help.txt"
$aboutHelpPath = Join-Path $EnUsPath "about_$ModuleName.help.txt"

if (Test-Path $aboutHelpSource) {
    Copy-Item -Path $aboutHelpSource -Destination $aboutHelpPath -Force
    Write-Host "  About help: $aboutHelpPath" -ForegroundColor Green
}
else {
    Write-Warning "About help source not found at $aboutHelpSource — about help skipped."
}

Write-Host "Build complete: $DistPath" -ForegroundColor Green
