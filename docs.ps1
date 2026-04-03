#Requires -Version 7.0
<#
.SYNOPSIS
    PlatyPS helper — generate, update, or build MAML help for this module.
.PARAMETER Generate
    Import the dev module and generate per-command Markdown files in ./docs/.
.PARAMETER Update
    Refresh existing Markdown files after editing function help.
.PARAMETER BuildHelp
    Produce MAML XML locally (./en-US/) for preview without a full build.
#>
param(
    [switch]$Generate,
    [switch]$Update,
    [switch]$BuildHelp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleName   = Split-Path $PSScriptRoot -Leaf
$ManifestPath = Join-Path $PSScriptRoot "src/$ModuleName.psd1"
$DocsPath     = Join-Path $PSScriptRoot 'docs'

# --- Auto-install PlatyPS ---
if (-not (Get-Module -Name PlatyPS -ListAvailable)) {
    Write-Host "PlatyPS not found — installing..." -ForegroundColor Yellow
    Install-Module PlatyPS -Scope CurrentUser -Force
}
Import-Module PlatyPS -Force

# --- Generate ---
if ($Generate) {
    Import-Module $ManifestPath -Force
    $exported = Get-Command -Module $ModuleName
    if (-not $exported) {
        Write-Warning "No exported functions found in $ModuleName. Ensure the module loads correctly."
        return
    }
    New-MarkdownHelp -Module $ModuleName -OutputFolder $DocsPath -Force
    Write-Host "Markdown help generated in $DocsPath" -ForegroundColor Green
    Write-Host "Tip: edit comment-based help in src/public/*.ps1, then run ./docs.ps1 -Update"
}

# --- Update ---
if ($Update) {
    Import-Module $ManifestPath -Force
    Update-MarkdownHelp -Path $DocsPath
    Write-Host "Markdown help updated in $DocsPath" -ForegroundColor Green
}

# --- Patch online version URLs (after Generate or Update) ---
if ($Generate -or $Update) {
    $manifest   = Import-PowerShellDataFile $ManifestPath
    $projectUri = $manifest.PrivateData.PSData.ProjectUri
    if ($projectUri) {
        $baseUrl = $projectUri.TrimEnd('/')
        Get-ChildItem $DocsPath -Filter *.md |
            Where-Object { $_.Name -notlike 'about_*' -and $_.Name -ne 'README.md' } |
            ForEach-Object {
                $url     = "$baseUrl/blob/main/docs/$($_.Name)"
                $content = Get-Content $_.FullName -Raw
                $updated = $content -replace '(?m)^online version:.*$', "online version: $url"
                if ($updated -ne $content) {
                    $updated | Set-Content $_.FullName -Encoding UTF8 -NoNewline
                    Write-Host "  Updated online version: $($_.Name)" -ForegroundColor Gray
                }
            }
    }
}

# --- Orphan cleanup (after Generate or Update) ---
if ($Generate -or $Update) {
    $currentFunctions = (Get-ChildItem (Join-Path $PSScriptRoot 'src/public') -Filter *.ps1).BaseName
    $orphans = Get-ChildItem $DocsPath -Filter *.md |
        Where-Object { $_.Name -notlike 'about_*' -and $_.Name -ne 'README.md' -and $_.BaseName -notin $currentFunctions }

    foreach ($orphan in $orphans) {
        Remove-Item $orphan.FullName -Force
        Write-Host "  Docs removed (orphan): $($orphan.Name)" -ForegroundColor Yellow
    }
}

# --- BuildHelp ---
if ($BuildHelp) {
    $EnUsPath = Join-Path $PSScriptRoot 'en-US'
    New-Item -ItemType Directory -Path $EnUsPath -Force | Out-Null
    New-ExternalHelp -Path $DocsPath -OutputPath $EnUsPath -Force | Out-Null

    $aboutHelpSource = Join-Path $DocsPath "about_$ModuleName.help.txt"
    $aboutHelpPath   = Join-Path $EnUsPath "about_$ModuleName.help.txt"
    if (Test-Path $aboutHelpSource) {
        Copy-Item -Path $aboutHelpSource -Destination $aboutHelpPath -Force
    } else {
        Write-Warning "About help source not found at $aboutHelpSource — about help skipped."
    }

    Write-Host "MAML XML written to $EnUsPath" -ForegroundColor Green
}

if (-not ($Generate -or $Update -or $BuildHelp)) {
    Write-Host "Usage: ./docs.ps1 [-Generate] [-Update] [-BuildHelp]"
}
