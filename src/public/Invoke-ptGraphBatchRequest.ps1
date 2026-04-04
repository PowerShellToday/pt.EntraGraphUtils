<#
.SYNOPSIS
    Executes multiple Microsoft Graph API requests in batches with automatic retry handling, rate limiting, and pagination support.

.DESCRIPTION
    This function processes multiple Microsoft Graph API requests efficiently by grouping them into batches of up to 20 requests.
    It handles rate limiting (HTTP 429 responses) with automatic retry logic, supports multiple pagination modes, and provides
    flexible output options including raw responses and grouped results. The function is designed to optimize API usage while
    respecting Microsoft Graph rate limits and providing robust error handling.

    The function supports three parameter sets:
    - Standard: Normal processing with individual item output and configurable pagination
    - GroupById: Groups results by request ID with automatic pagination (ideal for collecting complete datasets)
    - RawOutput: Returns complete batch response objects with configurable pagination (ideal for custom post-processing)

.PARAMETER BatchItems
    An array of PSCustomObject items representing individual Graph API requests. Each item must contain:
    - 'id' property: Unique identifier for tracking the request
    - 'url' property: The Graph API endpoint (relative to base URI and API version)
    - Optional: 'method', 'headers', 'body' properties for advanced requests

.PARAMETER GraphBaseUri
    The base URI for Microsoft Graph API. Supports different Graph environments:
    - https://graph.microsoft.com (default - Commercial cloud)
    - https://graph.microsoft.us (US Government cloud)
    - https://dod-graph.microsoft.us (US Government DoD cloud)
    - https://graph.microsoft.de (German cloud)
    - https://microsoftgraph.chinacloudapi.cn (China cloud)

.PARAMETER BatchSize
    The maximum number of requests to include in each batch. Must be between 1 and 20.
    Microsoft Graph supports up to 20 requests per batch operation. Defaults to 20.

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
    Switch parameter that returns complete batch response objects instead of processed results.
    When enabled:
    - Returns the raw Graph batch API responses
    - Pagination still works (if enabled) but responses aren't processed
    - Ideal for custom post-processing or debugging
    - Cannot be used with GroupById parameter
    - Great for using $count or other metadata from the response

.PARAMETER pagination
    Controls how the function handles paginated responses with @odata.nextLink. Valid values:
    - 'auto': Automatically follow all pagination links to retrieve complete datasets
    - 'none': Return only the first page of results without following pagination
    - Not specified: Return first page with warnings about available additional pages
    Note: Not available with GroupById parameter set (always uses 'auto')

.PARAMETER EnrichOutput
    Switch parameter that adds batch metadata to each output item. When enabled:
    - Adds a '@batchMetadata' property to each result object containing:
      * 'requestId': The batch request ID that returned this item
      * '@odata.context': The OData context URL from the response
    - Available in Standard and GroupById modes only (not available with RawOutput)
    - Helps track which batch request produced each result
    - Useful for debugging and audit trails

.OUTPUTS
    The output depends on the parameter set used:
    
    Standard mode: Individual result objects from successful requests
    GroupById mode: Hashtable with request IDs as keys and result arrays as values  
    RawOutput mode: Complete batch response objects from Graph API

.EXAMPLE
    $requests = @(
        New-ptGraphRequestItem -id "1" -url "/users"
        New-ptGraphRequestItem -id "2" -url "/groups"
    )
    Invoke-ptGraphBatchRequest -BatchItems $requests

    Processes two Graph API requests in standard mode. Returns individual user and group objects.
    Shows warnings if additional pages are available.

.EXAMPLE
    $requests = @(
        New-ptGraphRequestItem -id "users"  -url "/users"
        New-ptGraphRequestItem -id "groups" -url "/groups"
    )
    $results = Invoke-ptGraphBatchRequest -BatchItems $requests -GroupById
    $results["users"]  # All user objects
    $results["groups"] # All group objects

    Groups results by request ID with automatic pagination. Returns a hashtable where
    each key contains all results for that request type.

.EXAMPLE
    Invoke-ptGraphBatchRequest -BatchItems $requests -RawOutput -pagination 'auto'

    Returns raw batch response objects with automatic pagination. Useful for custom
    processing or when you need access to response metadata like status codes.

.EXAMPLE
    $largeRequests = @(
        New-ptGraphRequestItem -id "all-users"  -url "/users"
        New-ptGraphRequestItem -id "all-groups" -url "/groups"
    )
    Invoke-ptGraphBatchRequest -BatchItems $largeRequests -pagination 'auto'

    Automatically follows pagination to retrieve all users and groups. Each individual
    object is output as it's processed.

.EXAMPLE
    Invoke-ptGraphBatchRequest -BatchItems $requests -GraphBaseUri 'https://graph.microsoft.us' -ApiVersion 'beta'

    Processes requests using the US Government cloud endpoint with the beta API version.

.EXAMPLE
    Invoke-ptGraphBatchRequest -BatchItems $requests -pagination 'auto' -Verbose

    Processes batch items with automatic pagination and verbose output showing
    detailed progress information including batch counts and API call results.

.EXAMPLE
    $requests = @(
        New-ptGraphRequestItem -id "users"  -url "/users"
        New-ptGraphRequestItem -id "groups" -url "/groups"
    )
    $results = Invoke-ptGraphBatchRequest -BatchItems $requests -EnrichOutput -pagination 'auto'
    $results | Select-Object displayName, '@batchMetadata'

    Enriches each output item with batch metadata. Each result will have a '@batchMetadata' property
    containing the batch request ID and OData context, helpful for tracking data sources.

.NOTES
    - Requires the Microsoft.Graph PowerShell SDK for Invoke-MgGraphRequest
    - Automatically handles rate limiting with exponential backoff retry logic
    - Thread-safe queue implementation for reliable batch processing
    - Supports all Microsoft Graph sovereign cloud environments
    - Maximum 20 requests per batch (Microsoft Graph limitation)
    - Rate limit retry delays are extracted from Graph API error responses when available

.LINK
    https://docs.microsoft.com/en-us/graph/json-batching

.LINK
    https://docs.microsoft.com/en-us/graph/throttling

.LINK
    https://docs.microsoft.com/en-us/graph/paging
#>
function Invoke-ptGraphBatchRequest {
    [CmdletBinding(DefaultParameterSetName = 'Standard')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $true, ParameterSetName = 'GroupById')]
        [Parameter(Mandatory = $true, ParameterSetName = 'RawOutput')]
        [PSCustomObject[]] $BatchItems,

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

        # Specify Batch size.
        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'GroupById')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RawOutput')]
        [ValidateRange(1, 20)]
        [int] $BatchSize = 20,
        
        # Group results by batch id - only works with auto pagination
        [Parameter(Mandatory = $true, ParameterSetName = 'GroupById')]
        [switch] $GroupById,

        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'GroupById')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RawOutput')]
        [ValidateSet('v1.0', 'beta')]
        [string] $ApiVersion = 'v1.0',

        # Raw output - returns complete batch responses
        [Parameter(Mandatory = $true, ParameterSetName = 'RawOutput')]
        [switch]$RawOutput,

        # Pagination only available for Standard and RawOutput (GroupById always uses auto)
        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RawOutput')]
        [ValidateSet('none', 'auto')]
        [string]$pagination,

        # Enrich output with batch metadata (only for Standard and GroupById modes)
        [Parameter(Mandatory = $false, ParameterSetName = 'Standard')]
        [Parameter(Mandatory = $false, ParameterSetName = 'GroupById')]
        [switch]$EnrichOutput
    )

    begin {
        # Validate that all batch items have required properties
        $invalidItems = $BatchItems | Where-Object { -not $_.id -or -not $_.url -or -not $_.method }
        if ($invalidItems) {
            throw "All batch items must have 'id', 'method' and 'url' properties. Found $($invalidItems.Count) invalid item(s)."
        }
        
        # Determine pagination strategy based on parameter set
        # GroupById parameter set always uses auto pagination to ensure complete datasets
        if ($PSCmdlet.ParameterSetName -eq 'GroupById') {
            $pagination = 'auto'
        }
        # Note: When pagination is not specified, it remains empty string which triggers 
        # the 'default' case in the switch statement to show warnings
        
        # Initialize thread-safe queue for managing batch items during processing
        $queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
        
        # Initialize results collection if GroupById mode is enabled
        if ($GroupById) {
            $Results = @{}
        }

        # Populate the queue with all batch items and initialize result collections for GroupById
        $BatchItems | ForEach-Object {
            if ($GroupById) {
                $id = $_.id
                # Create a generic list for each unique ID to efficiently collect results
                $Results[$id] = New-Object 'System.Collections.Generic.List[psobject]'
            }
            # Add each item to the processing queue
            $queue.Enqueue($_)
        }
    }

    process {
        Write-Information ('Processing {0} requests in batches of {1}.' -f $BatchItems.Count, $BatchSize)
        Write-Verbose "Using parameter set: $($PSCmdlet.ParameterSetName)"
        Write-Verbose "Pagination mode: $(if ($pagination) { $pagination } else { 'default (warn)' })"
        
        # Initialize batch collection for current processing batch
        $batch = New-Object 'System.Collections.Generic.List[psobject]'
        
        # Construct the Graph API batch endpoint URI
        $uriQueryEndpoint = New-Object System.UriBuilder -ArgumentList ([IO.Path]::Combine($GraphBaseUri.AbsoluteUri, $ApiVersion, '$batch'))
        Write-Verbose "Batch endpoint: $($uriQueryEndpoint.Uri.AbsoluteUri)"

        # Track statistics for verbose output
        $batchCount = 0
        $totalProcessed = 0
        $pagesFollowed = 0

        # Main processing loop - continues until all items are processed
        do {
            $batchCount++
            Write-Information ('Items in queue: {0}' -f $queue.Count)
            Write-Verbose "Processing batch #$batchCount"
            
            # Fill the current batch up to the specified batch size
            while ($batch.Count -lt $BatchSize -and $queue.Count -gt 0) {
                $batch.Add($queue.Dequeue())
            }

            # Serialize batch requests to JSON format required by Graph batch API
            $jsonRequests = New-Object psobject -Property @{ requests = $batch } | ConvertTo-Json -Depth 5
            Write-Debug -Message "Batch Request JSON: $jsonRequests"

            # Execute the batch request if there are items to process
            if ($batch.Count) {
                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri $uriQueryEndpoint.Uri.AbsoluteUri -Body $jsonRequests -OutputType PSObject
                    Write-Verbose "Batch #$batchCount completed successfully with $($batchResponse.responses.Count) response(s)"
                }
                catch {
                    Write-Error "Failed to execute batch request #$batchCount : $_" -ErrorAction Stop
                    throw
                }
            }
            else {
                # Create empty response if batch is empty (shouldn't normally happen)
                $batchResponse = [PSCustomObject]@{ responses = @() }
            }
            
            # Initialize retry timer for rate limiting (429 responses)
            $RetryTimer = 0
            
            # Output raw batch response if RawOutput mode is enabled
            # This provides access to complete response metadata including status codes and headers
            if ($RawOutput) {
                Write-Output $batchResponse
            }

            # Process each individual response in the batch
            foreach ($response in $batchResponse.responses) {
                # Handle rate limiting (HTTP 429) - extract retry delay and continue
                if ($response.status -eq 429) {
                    $retryAfter = 15 # Default retry delay in seconds
                    $message = $response.body.error.message
                    # Try to extract specific retry delay from error message
                    if ($message -match 'Try again in (\d+) seconds') {
                        $retryAfter = [int]$matches[1]
                    }
                    # Track the longest retry delay if multiple 429s occur
                    if ($retryAfter -gt $RetryTimer) {
                        $RetryTimer = $retryAfter
                    }
                    continue
                } 
                # Handle all other non-success status codes (not 2xx)
                elseif ($response.status -notin 200..299) {
                    $errorMessage = "Graph API request failed with status $($response.status) for request ID '$($response.id)'"
                    # Include Graph API error message if available
                    if ($response.body.error.message) {
                        $errorMessage += ": $($response.body.error.message)"
                    }
                    Write-Debug -Message ($response | ConvertTo-Json -Depth 5)
                    Write-Error -Message $errorMessage -Category InvalidOperation -TargetObject $response
                    
                    # Remove failed item from batch to prevent infinite loop
                    $failedInstance = $batch.Find({ param($x) $x.id -eq $response.id })
                    if ($failedInstance) {
                        $batch.Remove($failedInstance) | Out-Null
                    }
                    continue
                }
                
                # Extract the request ID for tracking and result correlation
                $instanceId = $response.id
                $totalProcessed++

                # Process response body if not in raw output mode
                if (-not $RawOutput) {
                    # Ensure response has a body before processing
                    if (-not $response.body) {
                        Write-Warning "Response for request ID '$instanceId' has no body. Skipping."
                        
                        # Remove item with no body from batch to prevent infinite loop
                        $noBodyInstance = $batch.Find({ param($x) $x.id -eq $instanceId })
                        if ($noBodyInstance) {
                            $batch.Remove($noBodyInstance) | Out-Null
                        }
                        continue
                    }
                
                    # GroupById mode: Collect all results in hashtable keyed by request ID
                    if ($GroupById) {
                        # Check if value property is an array (typical for list responses)
                        if ($response.body.value -is [array]) {
                            # Add each item individually to maintain flat structure
                            $response.body.value | ForEach-Object {
                                # Enrich item with batch metadata if requested
                                if ($EnrichOutput) {
                                    $_ | Add-Member -NotePropertyName '@batchMetadata' -NotePropertyValue @{
                                        requestId        = $instanceId
                                        '@odata.context' = $response.body.'@odata.context'
                                    } -Force
                                }
                                $Results[$instanceId].Add($_)
                            }
                        }
                        else {
                            # Handle single object responses or responses without 'value' property
                            if ($EnrichOutput) {
                                $response.body | Add-Member -NotePropertyName '@batchMetadata' -NotePropertyValue @{
                                    requestId        = $instanceId
                                    '@odata.context' = $response.body.'@odata.context'
                                } -Force
                            }
                            $Results[$instanceId].Add($response.body)
                        }
                    } 
                    # Standard mode: Output individual items as they're processed
                    else {
                        # Check if response has a 'value' property (collection response)
                        if ($null -ne $response.body.PSObject.Properties['value']) {
                            # Check if value property is an array
                            if ($response.body.value -is [array]) {
                                # Output each item individually for pipeline processing
                                # Empty arrays won't output anything (correct behavior)
                                $response.body.value | ForEach-Object {
                                    # Enrich item with batch metadata if requested
                                    if ($EnrichOutput) {
                                        $_ | Add-Member -NotePropertyName '@batchMetadata' -NotePropertyValue @{
                                            requestId        = $instanceId
                                            '@odata.context' = $response.body.'@odata.context'
                                        } -Force
                                    }
                                    Write-Output $_
                                }
                            }
                            else {
                                # Handle single object in value property
                                if ($EnrichOutput) {
                                    $response.body.value | Add-Member -NotePropertyName '@batchMetadata' -NotePropertyValue @{
                                        requestId        = $instanceId
                                        '@odata.context' = $response.body.'@odata.context'
                                    } -Force
                                }
                                Write-Output $response.body.value
                            }
                        }
                        else {
                            # No value property - output the entire body (e.g., single entity GET)
                            if ($EnrichOutput) {
                                $response.body | Add-Member -NotePropertyName '@batchMetadata' -NotePropertyValue @{
                                    requestId        = $instanceId
                                    '@odata.context' = $response.body.'@odata.context'
                                } -Force
                            }
                            Write-Output $response.body
                        }
                    }
                }

                # Find the original batch item by response ID for pagination handling
                $instance = $batch.Find({ param($x) $x.id -eq $instanceId })
                
                # Validate that the batch item was found (should always exist)
                if (-not $instance) {
                    Write-Warning "Could not find batch item with ID '$instanceId' in current batch. Skipping pagination handling."
                    continue
                }

                # Handle pagination based on user preference and @odata.nextLink presence
                if ($response.body.'@odata.nextLink') {
                    switch ($pagination) {
                        'auto' {
                            # Automatically follow pagination - update URL and keep in batch
                            # Strip base URI and version to get relative URL for next page
                            $nextLink = $response.body.'@odata.nextLink'
                            # Extract the path after the API version (e.g., /v1.0/users?... -> /users?...)
                            if ($nextLink -match "$ApiVersion(.+)$") {
                                $instance.url = $matches[1]
                            }
                            else {
                                # Fallback: just strip base URI and version
                                $instance.url = $nextLink -replace ('{0}{1}' -f $GraphBaseUri.AbsoluteUri, $ApiVersion)
                            }
                            $pagesFollowed++
                        }
                        'none' {
                            # No pagination - remove from batch to stop processing this request
                            $batch.Remove($instance) | Out-Null
                        }
                        default {
                            # Pagination not specified - inform user about available pages and stop
                            Write-Warning "Request ID '$($response.id)' has additional pages available. Use -pagination 'auto' to retrieve all pages automatically, or 'none' to stop after first page."
                            $batch.Remove($instance) | Out-Null
                        }
                    }
                }
                else {
                    # No more pages available - remove completed request from batch
                    $batch.Remove($instance) | Out-Null
                }
            }

            # Apply rate limit delay if any 429 responses were encountered
            if ($RetryTimer) {
                Write-Information -MessageData "Rate limit exceeded, waiting $RetryTimer seconds"
                Start-Sleep -Seconds $RetryTimer
            }

        } while ($batch.Count -gt 0 -or $queue.Count -gt 0 )
        
        # Output final statistics
        Write-Verbose "Completed processing: $batchCount batch(es), $totalProcessed response(s), $pagesFollowed page(s) followed"
        
        # Output grouped results if GroupById mode was used
        if ($GroupById) {
            Write-Verbose "Returning grouped results for $($Results.Keys.Count) unique ID(s)"
            $Results.Clone()
        }
    }  
}