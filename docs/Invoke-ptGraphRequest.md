---
external help file: pt.EntraGraphUtils-help.xml
Module Name: pt.EntraGraphUtils
online version: https://github.com/PowerShellToday/pt.EntraGraphUtils/blob/main/docs/Invoke-ptGraphRequest.md
schema: 2.0.0
---

# Invoke-ptGraphRequest

## SYNOPSIS
Executes Microsoft Graph API requests individually with automatic retry handling, rate limiting, and pagination support.

## SYNTAX

### Standard (Default)
```
Invoke-ptGraphRequest -RequestItems <PSObject[]> [-GraphBaseUri <Uri>] [-ApiVersion <String>]
 [-pagination <String>] [-EnrichOutput] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### RawOutput
```
Invoke-ptGraphRequest -RequestItems <PSObject[]> [-GraphBaseUri <Uri>] [-ApiVersion <String>] [-RawOutput]
 [-pagination <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### GroupById
```
Invoke-ptGraphRequest -RequestItems <PSObject[]> [-GraphBaseUri <Uri>] [-GroupById] [-ApiVersion <String>]
 [-EnrichOutput] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
This function processes Microsoft Graph API requests one at a time.
It handles rate limiting (HTTP 429 responses) 
with automatic retry logic, supports multiple pagination modes, and provides flexible output options including 
raw responses and grouped results.
The function is designed to optimize API usage while respecting Microsoft Graph 
rate limits and providing robust error handling.

The function supports three parameter sets:
- Standard: Normal processing with individual item output and configurable pagination
- GroupById: Groups results by request ID with automatic pagination (ideal for collecting complete datasets)
- RawOutput: Returns complete response objects with configurable pagination (ideal for custom post-processing)

## EXAMPLES

### EXAMPLE 1
```
$requests = @(
    New-ptGraphRequestItem -id "1" -url "/users"
    New-ptGraphRequestItem -id "2" -url "/groups"
)
Invoke-ptGraphRequest -RequestItems $requests
```

Processes two Graph API requests individually.
Returns individual user and group objects.

### EXAMPLE 2
```
$requests = @(
    New-ptGraphRequestItem -id "users" -url "/users"
    New-ptGraphRequestItem -id "groups" -url "/groups"
)
$results = Invoke-ptGraphRequest -RequestItems $requests -GroupById
$results["users"]  # All user objects
$results["groups"] # All group objects
```

Groups results by request ID with automatic pagination.

### EXAMPLE 3
```
Invoke-ptGraphRequest -RequestItems $requests -RawOutput -pagination 'auto'
```

Returns raw response objects with automatic pagination.

### EXAMPLE 4
```
Invoke-ptGraphRequest -RequestItems $requests -pagination 'auto' -EnrichOutput
```

Processes requests with automatic pagination and enriches each output item with metadata.

## PARAMETERS

### -RequestItems
An array of PSCustomObject items representing individual Graph API requests.
Each item must contain:
- 'id' property: Unique identifier for tracking the request
- 'url' property: The Graph API endpoint (relative to base URI and API version)
- 'method' property: HTTP method (GET, POST, PUT, PATCH, DELETE)
- Optional: 'headers', 'body' properties for advanced requests

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -GraphBaseUri
The base URI for Microsoft Graph API.
Supports different Graph environments:
- https://graph.microsoft.com (default - Commercial cloud)
- https://graph.microsoft.us (US Government cloud)
- https://dod-graph.microsoft.us (US Government DoD cloud)
- https://graph.microsoft.de (German cloud)
- https://microsoftgraph.chinacloudapi.cn (China cloud)

```yaml
Type: Uri
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Https://graph.microsoft.com
Accept pipeline input: False
Accept wildcard characters: False
```

### -GroupById
Switch parameter that enables result grouping by request ID.
When used:
- Results are collected in a hashtable keyed by request ID
- Automatically enables 'auto' pagination to ensure complete datasets
- Returns a hashtable with request IDs as keys and arrays of results as values
- Cannot be used with RawOutput parameter

```yaml
Type: SwitchParameter
Parameter Sets: GroupById
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ApiVersion
The Microsoft Graph API version to use.
Valid values are 'v1.0' (default) or 'beta'.
Choose 'v1.0' for production stability or 'beta' for preview features.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: V1.0
Accept pipeline input: False
Accept wildcard characters: False
```

### -RawOutput
Switch parameter that returns complete response objects instead of processed results.
When enabled:
- Returns the raw Graph API responses
- Pagination still works (if enabled) but responses aren't processed
- Ideal for custom post-processing or debugging
- Cannot be used with GroupById parameter

```yaml
Type: SwitchParameter
Parameter Sets: RawOutput
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -pagination
Controls how the function handles paginated responses with @odata.nextLink.
Valid values:
- 'auto': Automatically follow all pagination links to retrieve complete datasets
- 'none': Return only the first page of results without following pagination
- Not specified: Return first page with warnings about available additional pages
Note: Not available with GroupById parameter set (always uses 'auto')

```yaml
Type: String
Parameter Sets: Standard, RawOutput
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -EnrichOutput
Switch parameter that adds request metadata to each output item.
When enabled:
- Adds a '@requestMetadata' property to each result object containing:
  * 'requestId': The request ID that returned this item
  * '@odata.context': The OData context URL from the response
- Available in Standard and GroupById modes only (not available with RawOutput)
- Helps track which request produced each result

```yaml
Type: SwitchParameter
Parameter Sets: Standard, GroupById
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### The output depends on the parameter set used:
### Standard mode: Individual result objects from successful requests
### GroupById mode: Hashtable with request IDs as keys and result arrays as values
### RawOutput mode: Complete response objects from Graph API
## NOTES
- Requires the Microsoft.Graph PowerShell SDK for Invoke-MgGraphRequest
- Automatically handles rate limiting with exponential backoff retry logic
- Supports all Microsoft Graph sovereign cloud environments
- Rate limit retry delays are extracted from Graph API error responses when available

## RELATED LINKS

[https://docs.microsoft.com/en-us/graph/throttling](https://docs.microsoft.com/en-us/graph/throttling)

[https://docs.microsoft.com/en-us/graph/paging](https://docs.microsoft.com/en-us/graph/paging)

