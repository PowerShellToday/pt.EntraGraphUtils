<#
.SYNOPSIS
    Creates a new Microsoft Graph request item for use with batch requests or individual API calls.

.DESCRIPTION
    This helper function creates properly formatted Graph request items that can be used with
    the Invoke-GraphBatchRequest2 function or for individual Graph API requests. It supports 
    different parameter sets for requests with and without body content, and handles both 
    string and hashtable body types.
    
    The function intelligently handles query parameters by:
    - Preserving existing query parameters from the input URL
    - Merging them with new OData parameters specified via function parameters
    - Allowing QueryParameters hashtable to override or add additional parameters
    - Properly URL-encoding the final query string

.PARAMETER id
    Unique identifier for the request within a batch operation. Used to correlate 
    batch responses with individual requests. Only used when this request item is 
    part of a batch request. If not specified, a new GUID will be automatically generated.

.PARAMETER url
    The Graph API endpoint URL (relative to the base URI, without the version prefix).
    Must start with a forward slash '/'. Can include existing query parameters which will
    be preserved and merged with any OData parameters specified via function parameters.
    Examples: "/users", "/groups/12345/members", "/me/messages", "/users?$top=5"

.PARAMETER method
    HTTP method for the request. Valid values: GET, POST, PUT, PATCH, DELETE.
    Defaults to 'GET' if not specified.

.PARAMETER headers
    Optional hashtable of HTTP headers to include with the request.
    When using body parameters, Content-Type will be automatically set to 'application/json'
    unless explicitly overridden via the ContentType parameter or headers hashtable.

.PARAMETER body
    Request body content. Can be either:
    - A hashtable object (will be converted to JSON automatically)
    - A pre-formatted JSON string (when you need precise control over formatting)
    The function automatically detects the type and handles it appropriately.

.PARAMETER bodyHashtable
    (Deprecated - use -body instead) Alias for -body parameter when passing a hashtable.

.PARAMETER bodyString
    (Deprecated - use -body instead) Alias for -body parameter when passing a string.

.PARAMETER dependsOn
    Optional identifier of another request within the same batch that this request depends on.
    Used to control execution order within batch operations. Only applicable when using 
    batch requests - ignored for individual API calls.

.PARAMETER pageSize
    Number of items to return per page (OData $top parameter).

.PARAMETER Count
    Include count of total items in response (OData $count parameter).

.PARAMETER ExpandProperty
    Expand related properties (OData $expand parameter).

.PARAMETER Filter
    Filter results based on criteria (OData $filter parameter).

.PARAMETER Format
    Response format (OData $format parameter).

.PARAMETER Sort
    Sort order for results (OData $orderby parameter).

.PARAMETER Search
    Search query (OData $search parameter).

.PARAMETER Property
    Select specific properties (OData $select parameter).

.PARAMETER Skip
    Number of items to skip (OData $skip parameter).

.PARAMETER skipToken
    Token for pagination (OData $skiptoken parameter).

.PARAMETER QueryParameters
    Optional hashtable of additional query parameters to include in the request URL.
    These parameters will be merged with any existing query parameters from the URL
    and any OData parameters specified via dedicated function parameters.
    QueryParameters take precedence over existing URL parameters with the same name.

.PARAMETER ConsistencyLevel
    Sets the consistency level for the request. Currently only 'eventual' is supported.
    Automatically adds the ConsistencyLevel header to the request when specified.

.PARAMETER ContentType
    Sets the Content-Type header for the request. If not specified, defaults to 'application/json'
    for requests with body content. Common values include: 'application/json' (default for most 
    Graph operations), 'application/x-www-form-urlencoded' (for OAuth), 'multipart/form-data' 
    (for file uploads), etc.

.OUTPUTS
    PSCustomObject
    Returns a properly formatted Graph request item object with all query parameters 
    (existing, OData, and custom) properly merged and URL-encoded in the final URL.

.EXAMPLE
    # Simple GET request (ID and method auto-generated/defaulted)
    $item1 = New-ptGraphRequestItem -url "/users"

.EXAMPLE
    # POST request with hashtable body and custom ID
    $item2 = New-ptGraphRequestItem -id "create-user" -url "/users" -method "POST" -headers @{"Content-Type"="application/json"} -body @{
        displayName = "John Doe"
        userPrincipalName = "john@contoso.com"
    }

.EXAMPLE
    # POST request with string body (auto-generated ID)
    $jsonBody = '{"displayName":"Jane Doe","userPrincipalName":"jane@contoso.com"}'
    $item3 = New-ptGraphRequestItem -url "/users" -method "POST" -headers @{"Content-Type"="application/json"} -body $jsonBody

.EXAMPLE
    # Backward compatibility: Using legacy -bodyHashtable parameter (aliased to -body)
    $item3b = New-ptGraphRequestItem -url "/users" -method "POST" -bodyHashtable @{
        displayName = "Legacy User"
        userPrincipalName = "legacy@contoso.com"
    }

.EXAMPLE
    # GET request with OData query parameters
    $item4 = New-ptGraphRequestItem -url "/users" -pageSize 10 -Filter "startswith(displayName,'John')" -Property "id,displayName,mail" -Sort "displayName"
    # Results in URL: /users?$top=10&$filter=startswith(displayName,'John')&$select=id,displayName,mail&$orderby=displayName

.EXAMPLE
    # URL with existing query parameters that get preserved and merged
    $item5 = New-ptGraphRequestItem -url "/users?$expand=manager" -pageSize 5 -Filter "department eq 'Sales'"
    # Results in URL: /users?$expand=manager&$top=5&$filter=department eq 'Sales'

.EXAMPLE
    # Using QueryParameters to add custom parameters
    $customParams = @{ 'api-version' = '2.0'; 'custom' = 'value' }
    $item6 = New-ptGraphRequestItem -url "/users" -QueryParameters $customParams -pageSize 10
    # Results in URL: /users?api-version=2.0&custom=value&$top=10

.NOTES
    - The function automatically handles the proper structure required by Graph API
    - Body content is only validated for type, not for Graph API schema compliance
    - Can be used for both batch operations and individual Graph API requests
    - The 'id' and 'dependsOn' parameters are only used for batch operations and are ignored for individual requests
    - Query parameters are intelligently merged: URL parameters + OData parameters + QueryParameters
    - Parameter precedence: QueryParameters > OData function parameters > existing URL parameters
    - All query parameters are properly URL-encoded in the final output
    - Uses internal module functions ConvertFrom-QueryString and ConvertTo-QueryString for query parameter processing
#>
function New-ptGraphRequestItem {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='None')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$id = [System.Guid]::NewGuid().ToString(),

        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if ($_ -notmatch '^/') {
                    throw "URL must start with '/'. Use relative URLs only. Example: '/users' instead of 'users' or 'https://graph.microsoft.com/v1.0/users'. Current value: '$_'"
                }
                return $true
            })]
        [string]$url,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$method = 'GET',

        [Parameter(Mandatory = $false)]
        [hashtable]$headers,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [Alias('bodyHashtable', 'bodyString')]
        [object]$body,

        [Parameter(Mandatory = $false)]
        [string]$dependsOn,

        # OData Query Parameters
        [Parameter(Mandatory = $false)]
        [Alias('$top')]
        [int]$pageSize,

        [Parameter(Mandatory = $false)]
        [Alias('$count')]
        [switch]$Count,

        [Parameter(Mandatory = $false)]
        [Alias('$expand')]
        [string]$ExpandProperty,

        [Parameter(Mandatory = $false)]
        [Alias('$filter')]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [Alias('$format')]
        [string]$Format,

        [Parameter(Mandatory = $false)]
        [Alias('$orderby')]
        [string]$Sort,

        [Parameter(Mandatory = $false)]
        [Alias('$search')]
        [string]$Search,

        [Parameter(Mandatory = $false)]
        [Alias('$select')]
        [string[]]$Property,

        [Parameter(Mandatory = $false)]
        [Alias('$skip')]
        [int]$Skip,

        [Parameter(Mandatory = $false)]
        [Alias('$skiptoken')]
        [string]$skipToken,

        # Parameters such as "$top".
        [Parameter(Mandatory = $false)]
        [hashtable] $QueryParameters,

        [Parameter(Mandatory = $false)]
        [ValidateSet('eventual')]
        [string] $ConsistencyLevel,

        [Parameter(Mandatory = $false)]
        [ValidateSet('application/json', 'application/x-www-form-urlencoded', 'multipart/form-data', 'application/octet-stream', 'text/plain')]
        [string] $ContentType

    )
    # Initialize URI builder
    $uriQueryEndpoint = [System.UriBuilder]::new("https://server.com$url")

    if ($uriQueryEndpoint.Query) {
        [hashtable] $odataParams = ConvertFrom-QueryString $uriQueryEndpoint.Query -AsHashtable
        if ($QueryParameters) {
            foreach ($ParameterName in $QueryParameters.Keys) {
                $odataParams[$ParameterName] = $QueryParameters[$ParameterName]
            }
        }
    } elseif ($QueryParameters) {
        [hashtable] $odataParams = $QueryParameters
    } else { 
        [hashtable] $odataParams = @{ } 
    }

    
    # Define OData parameter mappings
    $odataParameterMap = @{
        'pageSize'       = '$top'
        'Count'          = '$count'
        'ExpandProperty' = '$expand'
        'Filter'         = '$filter'
        'Format'         = '$format'
        'Sort'           = '$orderby'
        'Search'         = '$search'
        'Property'       = '$select'
        'Skip'           = '$skip'
        'skipToken'      = '$skiptoken'
    }
    
    # Process each bound parameter that's an OData parameter
    $PSBoundParameters.Keys | Where-Object { $odataParameterMap.ContainsKey($_) } | 
        ForEach-Object {
            $paramName = $_
            $paramValue = $PSBoundParameters[$paramName]
            $odataParamName = $odataParameterMap[$paramName]
        
            # Warn if this OData parameter already exists in the URL or QueryParameters
            if ($odataParams.ContainsKey($odataParamName)) {
                $existingValue = $odataParams[$odataParamName]
                if ($existingValue -ne $paramValue -and ($paramName -ne 'Count' -or $existingValue -ne 'true')) {
                    Write-Warning "OData parameter '$odataParamName' specified multiple times. Function parameter '-$paramName' value ('$paramValue') will override existing value ('$existingValue') from URL or QueryParameters."
                }
            }
        
            if ($paramName -eq 'Count' -and $paramValue) {
                # Count is a switch parameter
                $odataParams[$odataParamName] = 'true'
            } elseif ($paramName -eq 'Property' -and $paramValue.Count -gt 1) {
                # Property accepts string array - join with commas for OData $select
                $odataParams[$odataParamName] = $paramValue -join ','
            } else {
                $odataParams[$odataParamName] = $paramValue
            }
        }
    
    # Append query parameters to URL if any OData parameters were specified
    if ($odataParams.Count -gt 0) {
        $queryString = ConvertTo-QueryString $odataParams
        $url = $uriQueryEndpoint.Path + '?' + [uri]::UnescapeDataString($queryString)
    } else {
        # No query parameters, just use the path
        $url = $uriQueryEndpoint.Path
    }

    # Create the base batch item structure
    $batchItem = @{
        id     = $id
        url    = $url
        method = $method.ToUpper()
    }

    # consistencyLevel header
    if ($ConsistencyLevel) {
        if (-not $headers) {
            $headers = @{}
        }
        $headers['ConsistencyLevel'] = $ConsistencyLevel
    }

    # contentType header - set explicitly or default for body requests
    $finalContentType = $ContentType
    if (-not $finalContentType -and $PSBoundParameters.ContainsKey('body')) {
        # Default to application/json for body requests if not specified
        $finalContentType = 'application/json'
    }
    
    if ($finalContentType) {
        if (-not $headers) {
            $headers = @{}
        }
        # Warn if both ContentType parameter and headers["Content-Type"] are specified
        if ($ContentType -and $headers -and $headers.ContainsKey('Content-Type') -and $headers['Content-Type'] -ne $ContentType) {
            Write-Warning "Both -ContentType parameter ('$ContentType') and headers['Content-Type'] ('$($headers['Content-Type'])') are specified. The -ContentType parameter will override the header value."
        }
        $headers['Content-Type'] = $finalContentType
    }

    # Add headers if provided
    if ($headers) {
        $batchItem.headers = $headers
    }

    # Add body if provided
    if ($PSBoundParameters.ContainsKey('body')) {
        # Detect body type at runtime
        if ($body -is [hashtable]) {
            $batchItem.body = $body
        } elseif ($body -is [string]) {
            # Validate JSON if Content-Type suggests it should be JSON
            if ($finalContentType -eq 'application/json' -or (-not $ContentType -and -not ($headers -and $headers.ContainsKey('Content-Type')))) {
                try {
                    # Test if the string is valid JSON
                    $null = $body | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Warning "Body string does not appear to be valid JSON, but Content-Type is set to 'application/json' or not defined. Consider:"
                    Write-Warning '  1. Fix the JSON syntax in your body string'
                    Write-Warning "  2. Explicitly set -ContentType to the correct type (e.g., 'text/plain', 'application/x-www-form-urlencoded')"
                    Write-Warning '  3. Use a hashtable for -body instead for automatic JSON conversion'
                    Write-Warning "JSON validation error: $($_.Exception.Message)"
                }
            }
            $batchItem.body = $body
        } else {
            throw "Body must be either a hashtable or string. Received type: $($body.GetType().Name)"
        }
    } else {
        # Warn if using methods that typically require a body
        if ($method.ToUpper() -in @('POST', 'PUT', 'PATCH')) {
            Write-Warning "Using $($method.ToUpper()) method without a body. Consider:"
            Write-Warning '  1. Add -body with a hashtable for structured data that will be converted to JSON'
            Write-Warning '  2. Add -body with a string for pre-formatted content (JSON, form data, etc.)'
            Write-Warning '  3. If no body is intentional, you can ignore this warning'
        }
    }

    # Add dependency if specified
    if ($dependsOn) {
        $batchItem.dependsOn = $dependsOn
    }

    return [PSCustomObject]$batchItem
}
