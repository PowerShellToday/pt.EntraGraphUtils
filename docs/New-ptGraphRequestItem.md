---
external help file: pt.EntraGraphUtils-help.xml
Module Name: pt.EntraGraphUtils
online version: https://github.com/PowerShellToday/pt.EntraGraphUtils/blob/main/docs/New-ptGraphRequestItem.md
schema: 2.0.0
---

# New-ptGraphRequestItem

## SYNOPSIS
Creates a new Microsoft Graph request item for use with batch requests or individual API calls.

## SYNTAX

```
New-ptGraphRequestItem [[-id] <String>] [-url] <String> [[-method] <String>] [[-headers] <Hashtable>]
 [[-body] <Object>] [[-dependsOn] <String>] [[-pageSize] <Int32>] [-Count] [[-ExpandProperty] <String>]
 [[-Filter] <String>] [[-Format] <String>] [[-Sort] <String>] [[-Search] <String>] [[-Property] <String[]>]
 [[-Skip] <Int32>] [[-skipToken] <String>] [[-QueryParameters] <Hashtable>] [[-ConsistencyLevel] <String>]
 [[-ContentType] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
This helper function creates properly formatted Graph request items that can be used with
the Invoke-GraphBatchRequest2 function or for individual Graph API requests.
It supports 
different parameter sets for requests with and without body content, and handles both 
string and hashtable body types.

The function intelligently handles query parameters by:
- Preserving existing query parameters from the input URL
- Merging them with new OData parameters specified via function parameters
- Allowing QueryParameters hashtable to override or add additional parameters
- Properly URL-encoding the final query string

## EXAMPLES

### EXAMPLE 1
```
# Simple GET request (ID and method auto-generated/defaulted)
$item1 = New-ptGraphRequestItem -url "/users"
```

### EXAMPLE 2
```
# POST request with hashtable body and custom ID
$item2 = New-ptGraphRequestItem -id "create-user" -url "/users" -method "POST" -headers @{"Content-Type"="application/json"} -body @{
    displayName = "John Doe"
    userPrincipalName = "john@contoso.com"
}
```

### EXAMPLE 3
```
# POST request with string body (auto-generated ID)
$jsonBody = '{"displayName":"Jane Doe","userPrincipalName":"jane@contoso.com"}'
$item3 = New-ptGraphRequestItem -url "/users" -method "POST" -headers @{"Content-Type"="application/json"} -body $jsonBody
```

### EXAMPLE 4
```
# Backward compatibility: Using legacy -bodyHashtable parameter (aliased to -body)
$item3b = New-ptGraphRequestItem -url "/users" -method "POST" -bodyHashtable @{
    displayName = "Legacy User"
    userPrincipalName = "legacy@contoso.com"
}
```

### EXAMPLE 5
```
# GET request with OData query parameters
$item4 = New-ptGraphRequestItem -url "/users" -pageSize 10 -Filter "startswith(displayName,'John')" -Property "id,displayName,mail" -Sort "displayName"
# Results in URL: /users?$top=10&$filter=startswith(displayName,'John')&$select=id,displayName,mail&$orderby=displayName
```

### EXAMPLE 6
```
# URL with existing query parameters that get preserved and merged
$item5 = New-ptGraphRequestItem -url "/users?$expand=manager" -pageSize 5 -Filter "department eq 'Sales'"
# Results in URL: /users?$expand=manager&$top=5&$filter=department eq 'Sales'
```

### EXAMPLE 7
```
# Using QueryParameters to add custom parameters
$customParams = @{ 'api-version' = '2.0'; 'custom' = 'value' }
$item6 = New-ptGraphRequestItem -url "/users" -QueryParameters $customParams -pageSize 10
# Results in URL: /users?api-version=2.0&custom=value&$top=10
```

## PARAMETERS

### -id
Unique identifier for the request within a batch operation.
Used to correlate 
batch responses with individual requests.
Only used when this request item is 
part of a batch request.
If not specified, a new GUID will be automatically generated.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: [System.Guid]::NewGuid().ToString()
Accept pipeline input: False
Accept wildcard characters: False
```

### -url
The Graph API endpoint URL (relative to the base URI, without the version prefix).
Must start with a forward slash '/'.
Can include existing query parameters which will
be preserved and merged with any OData parameters specified via function parameters.
Examples: "/users", "/groups/12345/members", "/me/messages", "/users?$top=5"

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -method
HTTP method for the request.
Valid values: GET, POST, PUT, PATCH, DELETE.
Defaults to 'GET' if not specified.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: GET
Accept pipeline input: False
Accept wildcard characters: False
```

### -headers
Optional hashtable of HTTP headers to include with the request.
When using body parameters, Content-Type will be automatically set to 'application/json'
unless explicitly overridden via the ContentType parameter or headers hashtable.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -body
Request body content.
Can be either:
- A hashtable object (will be converted to JSON automatically)
- A pre-formatted JSON string (when you need precise control over formatting)
The function automatically detects the type and handles it appropriately.

```yaml
Type: Object
Parameter Sets: (All)
Aliases: bodyHashtable, bodyString

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -dependsOn
Optional identifier of another request within the same batch that this request depends on.
Used to control execution order within batch operations.
Only applicable when using 
batch requests - ignored for individual API calls.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -pageSize
Number of items to return per page (OData $top parameter).

```yaml
Type: Int32
Parameter Sets: (All)
Aliases: $top

Required: False
Position: 7
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -Count
Include count of total items in response (OData $count parameter).

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: $count

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExpandProperty
Expand related properties (OData $expand parameter).

```yaml
Type: String
Parameter Sets: (All)
Aliases: $expand

Required: False
Position: 8
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Filter
Filter results based on criteria (OData $filter parameter).

```yaml
Type: String
Parameter Sets: (All)
Aliases: $filter

Required: False
Position: 9
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Format
Response format (OData $format parameter).

```yaml
Type: String
Parameter Sets: (All)
Aliases: $format

Required: False
Position: 10
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Sort
Sort order for results (OData $orderby parameter).

```yaml
Type: String
Parameter Sets: (All)
Aliases: $orderby

Required: False
Position: 11
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Search
Search query (OData $search parameter).

```yaml
Type: String
Parameter Sets: (All)
Aliases: $search

Required: False
Position: 12
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Property
Select specific properties (OData $select parameter).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: $select

Required: False
Position: 13
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Skip
Number of items to skip (OData $skip parameter).

```yaml
Type: Int32
Parameter Sets: (All)
Aliases: $skip

Required: False
Position: 14
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -skipToken
Token for pagination (OData $skiptoken parameter).

```yaml
Type: String
Parameter Sets: (All)
Aliases: $skiptoken

Required: False
Position: 15
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -QueryParameters
Optional hashtable of additional query parameters to include in the request URL.
These parameters will be merged with any existing query parameters from the URL
and any OData parameters specified via dedicated function parameters.
QueryParameters take precedence over existing URL parameters with the same name.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 16
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ConsistencyLevel
Sets the consistency level for the request.
Currently only 'eventual' is supported.
Automatically adds the ConsistencyLevel header to the request when specified.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 17
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ContentType
Sets the Content-Type header for the request.
If not specified, defaults to 'application/json'
for requests with body content.
Common values include: 'application/json' (default for most 
Graph operations), 'application/x-www-form-urlencoded' (for OAuth), 'multipart/form-data' 
(for file uploads), etc.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 18
Default value: None
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

### PSCustomObject
### Returns a properly formatted Graph request item object with all query parameters
### (existing, OData, and custom) properly merged and URL-encoded in the final URL.
## NOTES
- The function automatically handles the proper structure required by Graph API
- Body content is only validated for type, not for Graph API schema compliance
- Can be used for both batch operations and individual Graph API requests
- The 'id' and 'dependsOn' parameters are only used for batch operations and are ignored for individual requests
- Query parameters are intelligently merged: URL parameters + OData parameters + QueryParameters
- Parameter precedence: QueryParameters \> OData function parameters \> existing URL parameters
- All query parameters are properly URL-encoded in the final output
- Uses internal module functions ConvertFrom-QueryString and ConvertTo-QueryString for query parameter processing

## RELATED LINKS
