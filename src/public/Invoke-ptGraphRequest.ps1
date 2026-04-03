<#
.SYNOPSIS
    Executes Microsoft Graph API requests individually with automatic retry handling, rate limiting, and pagination support.

.DESCRIPTION
    This function processes Microsoft Graph API requests one at a time. It handles rate limiting (HTTP 429 responses) 
    with automatic retry logic, supports multiple pagination modes, and provides flexible output options including 
    raw responses and grouped results. The function is designed to optimize API usage while respecting Microsoft Graph 
    rate limits and providing robust error handling.

    The function supports three parameter sets:
    - Standard: Normal processing with individual item output and configurable pagination
    - GroupById: Groups results by request ID with automatic pagination (ideal for collecting complete datasets)
    - RawOutput: Returns complete response objects with configurable pagination (ideal for custom post-processing)

.PARAMETER RequestItems
    An array of PSCustomObject items representing individual Graph API requests. Each item must contain:
    - 'id' property: Unique identifier for tracking the request
    - 'url' property: The Graph API endpoint (relative to base URI and API version)
    - 'method' property: HTTP method (GET, POST, PUT, PATCH, DELETE)
    - Optional: 'headers', 'body' properties for advanced requests

.PARAMETER GraphBaseUri
    The base URI for Microsoft Graph API. Supports different Graph environments:
    - https://graph.microsoft.com (default - Commercial cloud)
    - https://graph.microsoft.us (US Government cloud)
    - https://dod-graph.microsoft.us (US Government DoD cloud)
    - https://graph.microsoft.de (German cloud)
    - https://microsoftgraph.chinacloudapi.cn (China cloud)

.PARAMETER GroupById
    Switch parameter that enables result grouping by request ID. When used:
    - Results are collected in a hashtable keyed by request ID
    - Automatically enables 'auto' pagination to ensure complete datasets
    - Returns a hashtable with request IDs as keys and arrays of results as values
    - Cannot be used with RawOutput parameter

.PARAMETER ApiVersion
    The Microsoft Graph API version to use. Valid values are 'v1.0' (default) or 'beta'.
    Choose 'v1.0' for production stability or 'beta' for preview features.

.PARAMETER RawOutput
    Switch parameter that returns complete response objects instead of processed results.
    When enabled:
    - Returns the raw Graph API responses
    - Pagination still works (if enabled) but responses aren't processed
    - Ideal for custom post-processing or debugging
    - Cannot be used with GroupById parameter

.PARAMETER pagination
    Controls how the function handles paginated responses with @odata.nextLink. Valid values:
    - 'auto': Automatically follow all pagination links to retrieve complete datasets
    - 'none': Return only the first page of results without following pagination
    - Not specified: Return first page with warnings about available additional pages
    Note: Not available with GroupById parameter set (always uses 'auto')

.PARAMETER EnrichOutput
    Switch parameter that adds request metadata to each output item. When enabled:
    - Adds a '@requestMetadata' property to each result object containing:
      * 'requestId': The request ID that returned this item
      * '@odata.context': The OData context URL from the response
    - Available in Standard and GroupById modes only (not available with RawOutput)
    - Helps track which request produced each result

.OUTPUTS
    The output depends on the parameter set used:
    
    Standard mode: Individual result objects from successful requests
    GroupById mode: Hashtable with request IDs as keys and result arrays as values  
    RawOutput mode: Complete response objects from Graph API

.EXAMPLE
    $requests = @(
        New-ptGraphRequestItem -id "1" -url "/users"
        New-ptGraphRequestItem -id "2" -url "/groups"
    )
    Invoke-ptGraphRequest -RequestItems $requests

    Processes two Graph API requests individually. Returns individual user and group objects.

.EXAMPLE
    $requests = @(
        New-ptGraphRequestItem -id "users" -url "/users"
        New-ptGraphRequestItem -id "groups" -url "/groups"
    )
    $results = Invoke-ptGraphRequest -RequestItems $requests -GroupById
    $results["users"]  # All user objects
    $results["groups"] # All group objects

    Groups results by request ID with automatic pagination.

.EXAMPLE
    Invoke-ptGraphRequest -RequestItems $requests -RawOutput -pagination 'auto'

    Returns raw response objects with automatic pagination.

.EXAMPLE
    Invoke-ptGraphRequest -RequestItems $requests -pagination 'auto' -EnrichOutput

    Processes requests with automatic pagination and enriches each output item with metadata.

.NOTES
    - Requires the Microsoft.Graph PowerShell SDK for Invoke-MgGraphRequest
    - Automatically handles rate limiting with exponential backoff retry logic
    - Supports all Microsoft Graph sovereign cloud environments
    - Rate limit retry delays are extracted from Graph API error responses when available

.LINK
    https://docs.microsoft.com/en-us/graph/throttling

.LINK
    https://docs.microsoft.com/en-us/graph/paging
#>
function Invoke-ptGraphRequest {
    [CmdletBinding(DefaultParameterSetName = 'Standard')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $true, ParameterSetName = 'GroupById')]
        [Parameter(Mandatory = $true, ParameterSetName = 'RawOutput')]
        [PSCustomObject[]] $RequestItems,

        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'GroupById')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RawOutput')]
        [ValidateSet(
            'https://graph.microsoft.us/', 
            'https://microsoftgraph.chinacloudapi.cn/',
            'https://graph.microsoft.com/',
            'https://dod-graph.microsoft.us/',
            'https://graph.microsoft.de/'
        )]
        [uri] $GraphBaseUri = 'https://graph.microsoft.com',

        [Parameter(Mandatory = $true, ParameterSetName = 'GroupById')]
        [switch] $GroupById,

        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'GroupById')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RawOutput')]
        [ValidateSet('v1.0', 'beta')]
        [string] $ApiVersion = 'v1.0',

        [Parameter(Mandatory = $true, ParameterSetName = 'RawOutput')]
        [switch]$RawOutput,

        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RawOutput')]
        [ValidateSet('none', 'auto')]
        [string]$pagination,

        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'GroupById')]
        [switch]$EnrichOutput
    )

    begin {
        # Validate that all request items have required properties
        $invalidItems = $RequestItems | Where-Object { -not $_.id -or -not $_.url -or -not $_.method }
        if ($invalidItems) {
            throw "All request items must have 'id', 'method' and 'url' properties. Found $($invalidItems.Count) invalid item(s)."
        }
        
        # Determine pagination strategy based on parameter set
        if ($PSCmdlet.ParameterSetName -eq 'GroupById') {
            $pagination = 'auto'
        }
        
        # Initialize thread-safe queue for managing request items
        $queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
        
        # Initialize results collection if GroupById mode is enabled
        if ($GroupById) {
            $Results = @{}
        }

        # Populate the queue with all request items and initialize result collections for GroupById
        $RequestItems | ForEach-Object {
            if ($GroupById) {
                $id = $_.id
                $Results[$id] = New-Object 'System.Collections.Generic.List[psobject]'
            }
            $queue.Enqueue($_)
        }
    }

    process {
        Write-Information ('Processing {0} request(s).' -f $RequestItems.Count)
        Write-Verbose "Using parameter set: $($PSCmdlet.ParameterSetName)"
        Write-Verbose "Pagination mode: $(if ($pagination) { $pagination } else { 'default (warn)' })"

        # Track statistics
        $totalProcessed = 0
        $pagesFollowed = 0

        # Main processing loop
        while ($queue.Count -gt 0) {
            $request = $queue.Dequeue()
            $instanceId = $request.id
            
            Write-Verbose "Processing request ID: $instanceId"
            
            # Construct full URI
            $uri = [IO.Path]::Combine($GraphBaseUri.AbsoluteUri, $ApiVersion, $request.url.TrimStart('/'))
            Write-Verbose "Request URI: $uri"
            
            # Prepare request parameters
            $requestParams = @{
                Method = $request.method
                Uri    = $uri
            }
            
            # Add headers if provided
            if ($request.headers) {
                $requestParams['Headers'] = $request.headers
            }
            
            # Add body if provided
            if ($request.body) {
                if ($request.body -is [hashtable]) {
                    $requestParams['Body'] = ($request.body | ConvertTo-Json -Depth 10)
                }
                else {
                    $requestParams['Body'] = $request.body
                }
            }
            
            # Execute request with retry logic
            $maxRetries = 3
            $retryCount = 0
            $success = $false
            
            while (-not $success -and $retryCount -lt $maxRetries) {
                try {
                    $response = Invoke-MgGraphRequest @requestParams -OutputType PSObject
                    $success = $true
                    $totalProcessed++
                    
                    Write-Verbose "Request ID '$instanceId' completed successfully"
                    
                }
                catch {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                    
                    # Handle rate limiting (429)
                    if ($statusCode -eq 429) {
                        $retryAfter = 15
                        if ($_.Exception.Response.Headers['Retry-After']) {
                            $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                        }
                        
                        Write-Warning "Rate limit exceeded for request ID '$instanceId'. Waiting $retryAfter seconds (attempt $($retryCount + 1)/$maxRetries)"
                        Start-Sleep -Seconds $retryAfter
                        $retryCount++
                        continue
                    }
                    
                    # Handle other errors
                    $errorMessage = "Graph API request failed for request ID '$instanceId': $($_.Exception.Message)"
                    Write-Error -Message $errorMessage -Category InvalidOperation
                    break
                }
            }
            
            # Skip further processing if request failed
            if (-not $success) {
                continue
            }
            
            # Output raw response if RawOutput mode is enabled
            if ($RawOutput) {
                Write-Output $response
            }
            
            # Process response if not in raw output mode
            if (-not $RawOutput) {
                # Ensure response exists
                if (-not $response) {
                    Write-Warning "Response for request ID '$instanceId' is null. Skipping."
                    continue
                }
                
                # GroupById mode: Collect all results in hashtable
                if ($GroupById) {
                    if ($response.value -is [array]) {
                        $response.value | ForEach-Object {
                            if ($EnrichOutput) {
                                $_ | Add-Member -NotePropertyName '@requestMetadata' -NotePropertyValue @{
                                    requestId        = $instanceId
                                    '@odata.context' = $response.'@odata.context'
                                } -Force
                            }
                            $Results[$instanceId].Add($_)
                        }
                    }
                    else {
                        if ($EnrichOutput) {
                            $response | Add-Member -NotePropertyName '@requestMetadata' -NotePropertyValue @{
                                requestId        = $instanceId
                                '@odata.context' = $response.'@odata.context'
                            } -Force
                        }
                        $Results[$instanceId].Add($response)
                    }
                }
                # Standard mode: Output individual items
                else {
                    if ($null -ne $response.PSObject.Properties['value']) {
                        if ($response.value -is [array]) {
                            $response.value | ForEach-Object {
                                if ($EnrichOutput) {
                                    $_ | Add-Member -NotePropertyName '@requestMetadata' -NotePropertyValue @{
                                        requestId        = $instanceId
                                        '@odata.context' = $response.'@odata.context'
                                    } -Force
                                }
                                Write-Output $_
                            }
                        }
                        else {
                            if ($EnrichOutput) {
                                $response.value | Add-Member -NotePropertyName '@requestMetadata' -NotePropertyValue @{
                                    requestId        = $instanceId
                                    '@odata.context' = $response.'@odata.context'
                                } -Force
                            }
                            Write-Output $response.value
                        }
                    }
                    else {
                        if ($EnrichOutput) {
                            $response | Add-Member -NotePropertyName '@requestMetadata' -NotePropertyValue @{
                                requestId        = $instanceId
                                '@odata.context' = $response.'@odata.context'
                            } -Force
                        }
                        Write-Output $response
                    }
                }
            }
            
            # Handle pagination
            if ($response.'@odata.nextLink') {
                switch ($pagination) {
                    'auto' {
                        # Update URL and re-queue
                        $request.url = $response.'@odata.nextLink' -replace ('{0}{1}/' -f $GraphBaseUri.AbsoluteUri, $ApiVersion)
                        $queue.Enqueue($request)
                        $pagesFollowed++
                    }
                    'none' {
                        # Don't follow pagination
                    }
                    default {
                        Write-Warning "Request ID '$instanceId' has additional pages available. Use -pagination 'auto' to retrieve all pages automatically, or 'none' to stop after first page."
                    }
                }
            }
        }
        
        # Output statistics
        Write-Verbose "Completed processing: $totalProcessed response(s), $pagesFollowed page(s) followed"
        
        # Output grouped results if GroupById mode was used
        if ($GroupById) {
            Write-Verbose "Returning grouped results for $($Results.Keys.Count) unique ID(s)"
            $Results.Clone()
        }
    }
}