# Contributing to pt.EntraGraphUtils

## Prerequisites

- PowerShell 7.0+
- [Pester v5](https://pester.dev): `Install-Module Pester -RequiredVersion 5.* -Scope CurrentUser`
- [PlatyPS](https://github.com/PowerShell/platyPS): `Install-Module PlatyPS -Scope CurrentUser`
- [Microsoft.Graph](https://learn.microsoft.com/en-us/powershell/microsoftgraph/): `Install-Module Microsoft.Graph -Scope CurrentUser`

## Adding a new function

1. Create `src/public/<Verb-Noun>.ps1` (or `src/private/` for internal helpers).
2. Add full comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.OUTPUTS`.
3. Write a Pester test file at `tests/public/<Verb-Noun>.Tests.ps1`
   (or `tests/private/` for private functions using `InModuleScope`).
4. Run `./build.ps1` — it will auto-generate the `docs/<Verb-Noun>.md` file and compile the help XML.

## Running tests

```powershell
# Dev module tests
Invoke-Pester ./tests/ -Output Detailed

# Build + compiled output tests
./build.ps1 -Version '1.0.0' -Test
```

## Building

```powershell
# Full build (compiles, generates MAML, optionally runs tests)
./build.ps1 -Version '1.0.0'
./build.ps1 -Version '1.0.0' -Test

# Single-file build (no test flag)
./build-single-file.ps1 -Version '1.0.0'
```

Output lands in `dist/pt.EntraGraphUtils/`.

## Updating docs

Edit comment-based help directly in `src/public/*.ps1` — `build.ps1` keeps `docs/*.md` and the compiled help XML in sync automatically.

```powershell
# Preview compiled help locally without a full build:
./docs.ps1 -BuildHelp
```

## Release process

1. Update `CHANGELOG.md` — move items from `[Unreleased]` to a new version section.
2. Create and push a git tag: `git tag v1.0.0 && git push origin v1.0.0`
3. Create a GitHub release from the tag — the `publish.yml` workflow runs automatically.

## Code style

- Use approved PowerShell verbs (`Get-Verb` for reference).
- Support `-WhatIf`/`-Confirm` on any function that modifies state (`SupportsShouldProcess`).
- Write verbose output for significant state changes (`Write-Verbose`).
- Do not use `Write-Host` in library functions — reserve it for build/utility scripts.
- All public functions must have comment-based help with at least one `.EXAMPLE`.
