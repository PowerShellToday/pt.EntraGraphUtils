BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }

    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psm1") -Force

    function New-RequestItem {
        param ([string]$Id = '1', [string]$Url = '/users', [string]$Method = 'GET', [hashtable]$Headers, [object]$Body)

        $item = [ordered]@{
            id     = $Id
            url    = $Url
            method = $Method
        }

        if ($Headers) { $item.headers = $Headers }
        if ($PSBoundParameters.ContainsKey('Body')) { $item.body = $Body }

        [PSCustomObject]$item
    }
}

Describe 'Invoke-ptGraphRequest' {
    Context 'Parameter validation' {
        It 'RequestItems is mandatory' {
            $attr = (Get-Command Invoke-ptGraphRequest).Parameters['RequestItems'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            ($attr | Where-Object Mandatory | Select-Object -ExpandProperty Mandatory -Unique) | Should -Be @($true)
        }

        It 'throws when RequestItems entries are missing required properties' {
            $badItem = [PSCustomObject]@{ id = '1'; url = '/users' }
            { Invoke-ptGraphRequest -RequestItems $badItem } | Should -Throw
        }

        It 'GroupById and RawOutput cannot be used together' {
            $items = @(New-RequestItem)
            { Invoke-ptGraphRequest -RequestItems $items -GroupById -RawOutput } | Should -Throw
        }
    }

    Context 'Standard mode' {
        BeforeEach {
            $script:items = @(New-RequestItem -Id '1' -Url '/users' -Method 'GET')
            $response = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @(
                    [PSCustomObject]@{ id = 'u1'; displayName = 'Alice' }
                    [PSCustomObject]@{ id = 'u2'; displayName = 'Bob' }
                )
            }

            Mock Invoke-MgGraphRequest { $response } -ModuleName $ModuleName
        }

        It 'outputs each entry in response.value' {
            $result = Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none'
            $result.Count | Should -Be 2
            $result[0].displayName | Should -Be 'Alice'
            $result[1].displayName | Should -Be 'Bob'
        }

        It 'invokes Graph with the method from the request item' {
            Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none' | Out-Null
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Method -eq 'GET'
            }
        }

        It 'builds a URI with GraphBaseUri, ApiVersion and url' {
            Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none' | Out-Null
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/users'
            }
        }

        It 'passes headers when request item has headers' {
            $withHeaders = @(New-RequestItem -Headers @{ ConsistencyLevel = 'eventual' })
            Invoke-ptGraphRequest -RequestItems $withHeaders -pagination 'none' | Out-Null
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Headers.ConsistencyLevel -eq 'eventual'
            }
        }

        It 'serializes hashtable body to JSON string' {
            $withBody = @(New-RequestItem -Method 'POST' -Body @{ displayName = 'Test User' })
            Invoke-ptGraphRequest -RequestItems $withBody -pagination 'none' | Out-Null
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Body -is [string] -and $Body -match 'displayName'
            }
        }

        It 'adds request metadata when EnrichOutput is used' {
            $result = Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none' -EnrichOutput
            $result[0].'@requestMetadata'.requestId | Should -Be '1'
            $result[0].'@requestMetadata'.'@odata.context' | Should -Not -BeNullOrEmpty
        }

        It 'outputs a single non-array value property' {
            $singleValueResponse = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = [PSCustomObject]@{ id = 'u1'; displayName = 'Alice' }
            }
            Mock Invoke-MgGraphRequest { $singleValueResponse } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none'
            $result.id | Should -Be 'u1'
        }

        It 'enriches a single non-array value when EnrichOutput is used' {
            $singleValueResponse = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = [PSCustomObject]@{ id = 'u1'; displayName = 'Alice' }
            }
            Mock Invoke-MgGraphRequest { $singleValueResponse } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none' -EnrichOutput
            $result.'@requestMetadata'.requestId | Should -Be '1'
        }

        It 'outputs the entire response when no value property exists' {
            $entityResponse = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users/$entity'
                id               = 'u1'
                displayName      = 'Alice'
            }
            Mock Invoke-MgGraphRequest { $entityResponse } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none'
            $result.displayName | Should -Be 'Alice'
        }

        It 'enriches the entire response when no value property exists and EnrichOutput is used' {
            $entityResponse = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users/$entity'
                id               = 'u1'
                displayName      = 'Alice'
            }
            Mock Invoke-MgGraphRequest { $entityResponse } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $script:items -pagination 'none' -EnrichOutput
            $result.'@requestMetadata' | Should -Not -BeNullOrEmpty
            $result.'@requestMetadata'.requestId | Should -Be '1'
        }
    }

    Context 'RawOutput and GroupById modes' {
        It 'returns raw response when RawOutput is used' {
            $items = @(New-RequestItem)
            $response = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u1' }) }
            Mock Invoke-MgGraphRequest { $response } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $items -RawOutput -pagination 'none'
            $result | Should -Be $response
        }

        It 'returns hashtable keyed by request id in GroupById mode' {
            $items = @(
                New-RequestItem -Id 'users' -Url '/users'
                New-RequestItem -Id 'groups' -Url '/groups'
            )

            $script:call = 0
            Mock Invoke-MgGraphRequest {
                $script:call++
                if ($script:call -eq 1) {
                    [PSCustomObject]@{
                        '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                        value            = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
                    }
                }
                else {
                    [PSCustomObject]@{
                        '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#groups'
                        value            = @([PSCustomObject]@{ id = 'g1'; displayName = 'Admins' })
                    }
                }
            } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $items -GroupById
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'users'
            $result.Keys | Should -Contain 'groups'
            $result['users'][0].displayName | Should -Be 'Alice'
            $result['groups'][0].displayName | Should -Be 'Admins'
        }

        It 'enriches value array items in GroupById mode when EnrichOutput is used' {
            $items = @(
                New-RequestItem -Id 'users' -Url '/users'
                New-RequestItem -Id 'groups' -Url '/groups'
            )

            $script:call = 0
            Mock Invoke-MgGraphRequest {
                $script:call++
                if ($script:call -eq 1) {
                    [PSCustomObject]@{
                        '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                        value            = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
                    }
                }
                else {
                    [PSCustomObject]@{
                        '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#groups'
                        value            = @([PSCustomObject]@{ id = 'g1'; displayName = 'Admins' })
                    }
                }
            } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $items -GroupById -EnrichOutput
            $result['users'][0].'@requestMetadata'.requestId | Should -Be 'users'
        }

        It 'collects a non-array response body in GroupById mode' {
            $items = @(New-RequestItem -Id '1' -Url '/users/u1')

            $entityResponse = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users/$entity'
                id               = 'u1'
                displayName      = 'Alice'
            }
            Mock Invoke-MgGraphRequest { $entityResponse } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $items -GroupById
            $result['1'].Count | Should -Be 1
            $result['1'][0].displayName | Should -Be 'Alice'
        }
    }

    Context 'Body handling' {
        It 'passes a string body through without serialization' {
            $items = @(New-RequestItem -Method 'POST' -Body '{"displayName":"raw"}')
            $response = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u1' }) }
            Mock Invoke-MgGraphRequest { $response } -ModuleName $ModuleName

            Invoke-ptGraphRequest -RequestItems $items -pagination 'none' | Out-Null
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Body -is [string] -and $Body -eq '{"displayName":"raw"}'
            }
        }
    }

    Context 'Error handling — catch block' {
        BeforeEach {
            Mock Start-Sleep {} -ModuleName $ModuleName

            $script:fakeEx = [System.Exception]::new('Rate limited')
            $script:fakeEx | Add-Member -NotePropertyName Response -NotePropertyValue (
                [PSCustomObject]@{
                    StatusCode = [PSCustomObject]@{ value__ = 429 }
                    Headers    = @{ 'Retry-After' = '3' }
                }
            ) -Force

            $successResponse = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }
            $script:successResponse = $successResponse
        }

        It 'writes a non-terminating error when a non-429 exception is thrown' {
            Mock Invoke-MgGraphRequest { throw 'Network error' } -ModuleName $ModuleName

            Invoke-ptGraphRequest -RequestItems @(New-RequestItem) -pagination 'none' `
                -ErrorAction SilentlyContinue -ErrorVariable errs | Out-Null
            $errs | Should -Not -BeNullOrEmpty
        }

        It 'continues to the next request after a non-retryable error' {
            $script:call = 0
            Mock Invoke-MgGraphRequest {
                $script:call++
                if ($script:call -eq 1) { throw 'Network error' }
                else { $script:successResponse }
            } -ModuleName $ModuleName

            $items = @(
                New-RequestItem -Id '1' -Url '/users'
                New-RequestItem -Id '2' -Url '/groups'
            )
            $result = Invoke-ptGraphRequest -RequestItems $items -pagination 'none' `
                -ErrorAction SilentlyContinue
            $result.Count | Should -Be 1
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 2
        }

        It 'retries on a 429 exception and eventually succeeds' {
            $script:call = 0
            Mock Invoke-MgGraphRequest {
                $script:call++
                if ($script:call -eq 1) { throw $script:fakeEx }
                else { $script:successResponse }
            } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems @(New-RequestItem) -pagination 'none'
            $result.Count | Should -Be 1
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 2
            Should -Invoke Start-Sleep -ModuleName $ModuleName -Times 1 -ParameterFilter {
                $Seconds -eq 3
            }
        }

        It 'exhausts retries on repeated 429 and produces no output' {
            Mock Invoke-MgGraphRequest { throw $script:fakeEx } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems @(New-RequestItem) -pagination 'none' `
                -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            Should -Invoke Start-Sleep -ModuleName $ModuleName -Times 3
        }
    }

    Context 'Null response handling' {
        It 'warns and produces no output when the response is null' {
            Mock Invoke-MgGraphRequest { $null } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems @(New-RequestItem) -pagination 'none' `
                -WarningVariable warnings 3>$null
            $result | Should -BeNullOrEmpty
            $warnings | Should -Match 'null'
        }
    }

    Context 'Pagination behavior' {
        It 'follows nextLink when pagination is auto' {
            $items = @(New-RequestItem -Id '1' -Url '/users')

            $page1 = [PSCustomObject]@{
                '@odata.context'  = 'https://graph.microsoft.com/v1.0/$metadata#users'
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                value             = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }
            $page2 = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#users'
                value            = @([PSCustomObject]@{ id = 'u2'; displayName = 'Bob' })
            }

            $script:call = 0
            Mock Invoke-MgGraphRequest {
                $script:call++
                if ($script:call -eq 1) { $page1 } else { $page2 }
            } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $items -pagination 'auto'
            $result.Count | Should -Be 2
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 2
        }

        It 'stops after first page when pagination is none' {
            $items = @(New-RequestItem -Id '1' -Url '/users')
            $page = [PSCustomObject]@{
                '@odata.context'  = 'https://graph.microsoft.com/v1.0/$metadata#users'
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                value             = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }

            Mock Invoke-MgGraphRequest { $page } -ModuleName $ModuleName

            $result = Invoke-ptGraphRequest -RequestItems $items -pagination 'none'
            $result.Count | Should -Be 1
            Should -Invoke Invoke-MgGraphRequest -ModuleName $ModuleName -Times 1
        }

        It 'warns when nextLink exists and pagination is not specified' {
            $items = @(New-RequestItem -Id '1' -Url '/users')
            $page = [PSCustomObject]@{
                '@odata.context'  = 'https://graph.microsoft.com/v1.0/$metadata#users'
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                value             = @([PSCustomObject]@{ id = 'u1'; displayName = 'Alice' })
            }

            Mock Invoke-MgGraphRequest { $page } -ModuleName $ModuleName

            Invoke-ptGraphRequest -RequestItems $items -WarningVariable warnings 3>$null | Out-Null
            $warnings | Should -Match 'additional pages'
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
