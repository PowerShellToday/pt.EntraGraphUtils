# pt.EntraGraphUtils

PowerShell utilities for the Microsoft Graph REST API.

## Overview

`pt.EntraGraphUtils` provides general-purpose functions for interacting with the
Microsoft Graph API, with support for JSON batching, automatic retry/rate-limit
handling, auto-pagination, and OData query parameters.

All public commands call `Invoke-MgGraphRequest` internally and require the
`Microsoft.Graph.Authentication` module. Connect before calling any command:

```powershell
Connect-MgGraph -Scopes 'User.Read.All', 'Group.Read.All'
```

## Exported Commands

| Command | Description |
| --- | --- |
| [Invoke-ptGraphBatchRequest](Invoke-ptGraphBatchRequest.md) | Execute multiple Graph API requests in a single batch call with automatic retry and pagination |
| [Invoke-ptGraphRequest](Invoke-ptGraphRequest.md) | Execute a single Graph API request with automatic retry and pagination |
| [New-ptGraphRequestItem](New-ptGraphRequestItem.md) | Build a Graph request item (for batch or individual use) with OData parameter support |

## Attributions

The following internal helper functions are adapted from the
[Utility.PS](https://github.com/jazuntee/Utility.PS) project by Jason Thompson (jazuntee),
used under the MIT License:

- `ConvertFrom-QueryString`
- `ConvertTo-QueryString`

## Generating / Updating Documentation

This module uses [PlatyPS](https://github.com/PowerShell/platyPS) for help generation.

```powershell
# First time — generate Markdown from comment-based help
./docs.ps1 -Generate

# After editing function help — refresh Markdown
./docs.ps1 -Update

# Build MAML XML locally
./docs.ps1 -BuildHelp
```

> Each exported command must have its own `.md` file in this folder.
> A single combined file will produce an empty MAML XML.
