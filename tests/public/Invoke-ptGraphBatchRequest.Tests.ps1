BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psd1") -Force

    # Helper: build a minimal valid batch item
    function New-BatchItem {
        param ([string]$Id = '1', [string]$Url = 'users', [string]$Method = 'GET')
        [PSCustomObject]@{ id = $Id; url = $Url; method = $Method }
    }

    # Helper: build a standard Graph batch response envelope
    function New-BatchResponse {
        param ([array]$Responses)
        [PSCustomObject]@{ responses = $Responses }
    }

    # Helper: build a single Graph batch response entry
    function New-ResponseEntry {
        param (
            [string]$Id = '1',
            [int]   $Status = 200,
            [object]$Body = $null
        )
        [PSCustomObject]@{ id = $Id; status = $Status; body = $Body }
    }
}

Describe 'Invoke-ptGraphBatchRequest' {

    # ------------------------------------------------------------------ #
    #  Parameter validation                                                #
    # ------------------------------------------------------------------ #
    Context 'Parameter validation' {
        It 'BatchItems is mandatory' {
            $cmd = Get-Command Invoke-ptGraphBatchRequest
            $attr = $cmd.Parameters['BatchItems'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatoryAttributes = $attr | Where-Object Mandatory
            $mandatoryAttributes.Count | Should -BeGreaterThan 0
            $mandatoryAttributes.Mandatory | Should -Contain $true
        }

        It 'BatchSize defaults to 20' {
            $items = 1..21 | ForEach-Object {
                New-BatchItem -Id "$_" -Url "users/$_" -Method 'GET'
            }

            Mock Invoke-MgGraphRequest {
                $requests = $Body | ConvertFrom-Json -Depth 5 | Select-Object -ExpandProperty requests
                $responses = foreach ($request in $requests) {
                    [PSCustomObject]@{
                        id     = $request.id
                        status = 200
                        body   = [PSCustomObject]@{ value = @() }
                    }
                }

                [PSCustomObject]@{ responses = $responses }
            } -ModuleName $ModuleName

            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 2
        }

        It 'BatchSize rejects values outside 1-20' {
            { Invoke-ptGraphBatchRequest -BatchItems (New-BatchItem) -BatchSize 0 } | Should -Throw
            { Invoke-ptGraphBatchRequest -BatchItems (New-BatchItem) -BatchSize 21 } | Should -Throw
        }

        It 'ApiVersion only accepts v1.0 or beta' {
            $cmd = Get-Command Invoke-ptGraphBatchRequest
            $validateSet = $cmd.Parameters['ApiVersion'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'v1.0'
            $validateSet.ValidValues | Should -Contain 'beta'
            $validateSet.ValidValues.Count | Should -Be 2
        }

        It 'pagination only accepts none or auto' {
            $cmd = Get-Command Invoke-ptGraphBatchRequest
            $validateSet = $cmd.Parameters['pagination'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'none'
            $validateSet.ValidValues | Should -Contain 'auto'
        }

        It 'throws when a batch item is missing the method property' {
            $badItem = [PSCustomObject]@{ id = '1'; url = 'users' }
            { Invoke-ptGraphBatchRequest -BatchItems $badItem } | Should -Throw -ExpectedMessage "*method*"
        }

        It 'throws when a batch item is missing the id property' {
            $badItem = [PSCustomObject]@{ url = 'users'; method = 'GET' }
            { Invoke-ptGraphBatchRequest -BatchItems $badItem } | Should -Throw
        }

        It 'throws when a batch item is missing the url property' {
            $badItem = [PSCustomObject]@{ id = '1'; method = 'GET' }
            { Invoke-ptGraphBatchRequest -BatchItems $badItem } | Should -Throw
        }

        It 'GroupById and RawOutput cannot be used together' {
            { Invoke-ptGraphBatchRequest -BatchItems (New-BatchItem) -GroupById -RawOutput } | Should -Throw
        }
    }

    # ------------------------------------------------------------------ #
    #  Standard mode                                                       #
    # ------------------------------------------------------------------ #
    Context 'Standard mode — value array responses' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users' -Method 'GET')

            $responseBody = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @(
                    [PSCustomObject]@{ id = 'u1'; displayName = 'Alice' }
                    [PSCustomObject]@{ id = 'u2'; displayName = 'Bob' }
                )
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $responseBody)
            } -ModuleName $ModuleName
        }

        It 'outputs individual objects from the value array' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            $result.Count | Should -Be 2
            $result[0].displayName | Should -Be 'Alice'
            $result[1].displayName | Should -Be 'Bob'
        }

        It 'calls Invoke-MgGraphRequest with POST' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'uses the correct batch endpoint for v1.0' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Uri -like '*graph.microsoft.com*v1.0*$batch*'
            }
        }

        It 'uses beta endpoint when ApiVersion is beta' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none' -ApiVersion 'beta'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Uri -like '*beta*$batch*'
            }
        }
    }

    Context 'Standard mode — single entity (no value property)' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users/u1' -Method 'GET')

            $responseBody = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users/$entity'
                id               = 'u1'
                displayName      = 'Alice'
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $responseBody)
            } -ModuleName $ModuleName
        }

        It 'outputs the response body directly when no value property exists' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            $result.displayName | Should -Be 'Alice'
        }
    }

    # ------------------------------------------------------------------ #
    #  EnrichOutput                                                        #
    # ------------------------------------------------------------------ #
    Context 'EnrichOutput — adds @batchMetadata' {
        BeforeEach {
            $items = @(New-BatchItem -Id 'req1' -Url 'users' -Method 'GET')

            $responseBody = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @(
                    [PSCustomObject]@{ id = 'u1'; displayName = 'Alice' }
                )
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id 'req1' -Status 200 -Body $responseBody)
            } -ModuleName $ModuleName
        }

        It 'adds @batchMetadata with requestId' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -EnrichOutput -pagination 'none'
            $result.'@batchMetadata'.requestId | Should -Be 'req1'
        }

        It 'adds @batchMetadata with @odata.context' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -EnrichOutput -pagination 'none'
            $result.'@batchMetadata'.'@odata.context' | Should -Not -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------ #
    #  GroupById mode                                                      #
    # ------------------------------------------------------------------ #
    Context 'GroupById mode' {
        BeforeEach {
            $items = @(
                New-BatchItem -Id 'users'  -Url 'users'  -Method 'GET'
                New-BatchItem -Id 'groups' -Url 'groups' -Method 'GET'
            )

            $usersBody = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @(
                    [PSCustomObject]@{ id = 'u1'; displayName = 'Alice' }
                    [PSCustomObject]@{ id = 'u2'; displayName = 'Bob' }
                )
            }
            $groupsBody = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#groups'
                value            = @(
                    [PSCustomObject]@{ id = 'g1'; displayName = 'Admins' }
                )
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(
                    New-ResponseEntry -Id 'users'  -Status 200 -Body $usersBody
                    New-ResponseEntry -Id 'groups' -Status 200 -Body $groupsBody
                )
            } -ModuleName $ModuleName
        }

        It 'returns a hashtable' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -GroupById
            $result | Should -BeOfType [hashtable]
        }

        It 'keys match request IDs' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -GroupById
            $result.Keys | Should -Contain 'users'
            $result.Keys | Should -Contain 'groups'
        }

        It 'each key holds the correct number of items' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -GroupById
            $result['users'].Count  | Should -Be 2
            $result['groups'].Count | Should -Be 1
        }

        It 'items are accessible by name' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -GroupById
            $result['users'][0].displayName | Should -Be 'Alice'
        }

        It 'adds @batchMetadata when EnrichOutput is specified' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -GroupById -EnrichOutput
            $result['users'][0].'@batchMetadata'.requestId | Should -Be 'users'
        }
    }

    # ------------------------------------------------------------------ #
    #  RawOutput mode                                                      #
    # ------------------------------------------------------------------ #
    Context 'RawOutput mode' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users' -Method 'GET')

            $body = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @([PSCustomObject]@{ id = 'u1' })
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $body)
            } -ModuleName $ModuleName
        }

        It 'returns the raw batch envelope with a responses property' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -RawOutput -pagination 'none'
            $result.responses | Should -Not -BeNullOrEmpty
        }

        It 'raw responses contain status codes' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -RawOutput -pagination 'none'
            $result.responses[0].status | Should -Be 200
        }
    }

    # ------------------------------------------------------------------ #
    #  Rate limiting (HTTP 429)                                            #
    # ------------------------------------------------------------------ #
    Context 'Rate limiting — 429 handling' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users' -Method 'GET')

            $rateLimitBody = [PSCustomObject]@{
                error = [PSCustomObject]@{ message = 'Try again in 2 seconds' }
            }
            $successBody = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }

            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 429 -Body $rateLimitBody)
                }
                else {
                    New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $successBody)
                }
            } -ModuleName $ModuleName

            Mock Start-Sleep {} -ModuleName $ModuleName
        }

        It 'retries after a 429 response and eventually succeeds' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            $result.displayName | Should -Be 'Alice'
        }

        It 'calls Invoke-MgGraphRequest more than once when rate limited' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 2
        }

        It 'calls Start-Sleep with the retry delay from the error message' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            Should -Invoke Start-Sleep -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Seconds -eq 2
            }
        }
    }

    # ------------------------------------------------------------------ #
    #  Non-success (non-429) errors                                        #
    # ------------------------------------------------------------------ #
    Context 'Non-success error handling' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users/nonexistent' -Method 'GET')

            $errorBody = [PSCustomObject]@{
                error = [PSCustomObject]@{ message = 'Resource not found' }
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 404 -Body $errorBody)
            } -ModuleName $ModuleName
        }

        It 'writes an error for non-2xx responses' {
            { Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none' -ErrorAction Stop } |
            Should -Throw
        }
    }

    # ------------------------------------------------------------------ #
    #  Pagination                                                          #
    # ------------------------------------------------------------------ #
    Context 'Pagination — auto follows nextLink' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users' -Method 'GET')

            $page1Body = [PSCustomObject]@{
                '@odata.context'  = 'https://graph.microsoft.com/v1.0/$metadata#users'
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                value             = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }
            $page2Body = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @([PSCustomObject]@{ id = 'u2'; displayName = 'Bob' })
            }

            $script:callCount = 0
            Mock Invoke-MgGraphRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $page1Body)
                }
                else {
                    New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $page2Body)
                }
            } -ModuleName $ModuleName
        }

        It 'returns all items across pages when pagination is auto' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'auto'
            $result.Count | Should -Be 2
        }

        It 'calls Invoke-MgGraphRequest twice (once per page)' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'auto'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 2
        }
    }

    Context 'Pagination — none stops after first page' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users' -Method 'GET')

            $pageBody = [PSCustomObject]@{
                '@odata.context'  = 'https://graph.microsoft.com/v1.0/$metadata#users'
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                value             = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $pageBody)
            } -ModuleName $ModuleName
        }

        It 'calls Invoke-MgGraphRequest exactly once when pagination is none' {
            Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1
        }

        It 'returns only the first page of results' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -pagination 'none'
            $result.Count | Should -Be 1
        }
    }

    Context 'Pagination — default emits a warning when nextLink is present' {
        BeforeEach {
            $items = @(New-BatchItem -Id '1' -Url 'users' -Method 'GET')

            $pageBody = [PSCustomObject]@{
                '@odata.context'  = 'https://graph.microsoft.com/v1.0/$metadata#users'
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                value             = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }

            Mock Invoke-MgGraphRequest {
                New-BatchResponse -Responses @(New-ResponseEntry -Id '1' -Status 200 -Body $pageBody)
            } -ModuleName $ModuleName
        }

        It 'writes a warning about additional pages' {
            Invoke-ptGraphBatchRequest -BatchItems $items -WarningVariable warnings 3>$null
            $warnings | Should -Match 'additional pages'
        }
    }

    # ------------------------------------------------------------------ #
    #  Batching — splits large input into multiple batch calls             #
    # ------------------------------------------------------------------ #
    Context 'Batching — splits requests into batches of BatchSize' {
        BeforeEach {
            # 25 items, BatchSize 10 → should produce 3 batch calls
            $items = 1..25 | ForEach-Object {
                New-BatchItem -Id "$_" -Url "users/$_" -Method 'GET'
            }

            Mock Invoke-MgGraphRequest {
                $responses = $Body | ConvertFrom-Json -Depth 5 |
                Select-Object -ExpandProperty requests |
                ForEach-Object {
                    $singleBody = [PSCustomObject]@{
                        '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users/$entity'
                        id               = $_.id
                        displayName      = "User $($_.id)"
                    }
                    New-ResponseEntry -Id $_.id -Status 200 -Body $singleBody
                }
                New-BatchResponse -Responses $responses
            } -ModuleName $ModuleName
        }

        It 'calls Invoke-MgGraphRequest 3 times for 25 items with BatchSize 10' {
            Invoke-ptGraphBatchRequest -BatchItems $items -BatchSize 10 -pagination 'none'
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 3
        }

        It 'returns one result per input item' {
            $result = Invoke-ptGraphBatchRequest -BatchItems $items -BatchSize 10 -pagination 'none'
            $result.Count | Should -Be 25
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
