# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1-RC1] - 2026-04-04

### Added

- `Invoke-ptGraphBatchRequest` — executes multiple Graph API requests as a single JSON batch, auto-chunking any number of items into groups of 20 (the Graph API limit), with automatic retry, rate-limit backoff, and pagination support
- `Invoke-ptGraphRequest` — executes individual Graph API requests with automatic retry, rate-limit backoff, and pagination support
- `New-ptGraphRequestItem` — builds a Graph request object with full OData parameter support (`-Filter`, `-Property`, `-Sort`, `-pageSize`, `-QueryParameters`) and intelligent URL parameter merging
- PlatyPS-based documentation workflow (`docs.ps1 -Generate / -Update / -BuildHelp`)
- `build.ps1` and `build-single-file.ps1` compilation scripts
- Pester v5 test suite (module, public, and private tests)
- GitHub Actions CI (push/PR) and publish (release) workflows
- Requires `Microsoft.Graph.Authentication` — all functions call `Invoke-MgGraphRequest` internally

[1.0.0]: https://github.com/PowerShellToday/pt.EntraGraphUtils/releases/tag/v1.0.0
