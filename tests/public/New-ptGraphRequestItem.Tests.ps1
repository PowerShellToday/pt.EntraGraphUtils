BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }

    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psm1") -Force
}

Describe 'New-ptGraphRequestItem' {
    Context 'Basic shape and defaults' {
        It 'creates an object with id, url and method' {
            $item = New-ptGraphRequestItem -url '/users'

            $item.id | Should -Not -BeNullOrEmpty
            $item.url | Should -Be '/users'
            $item.method | Should -Be 'GET'
        }

        It 'uses uppercase method value' {
            $item = New-ptGraphRequestItem -url '/users' -method 'patch'
            $item.method | Should -Be 'PATCH'
        }

        It 'throws when url does not start with slash' {
            { New-ptGraphRequestItem -url 'users' } | Should -Throw
        }
    }

    Context 'OData and query parameter handling' {
        It 'adds OData parameters from function parameters' {
            $item = New-ptGraphRequestItem -url '/users' -pageSize 5 -Filter "startswith(displayName,'A')"

            $item.url | Should -Match '\$top=5'
            $item.url | Should -Match '\$filter='
        }

        It 'joins Property array into a comma-separated $select' {
            $item = New-ptGraphRequestItem -url '/users' -Property @('id', 'displayName', 'mail')
            $item.url | Should -Match '\$select=id,displayName,mail'
        }

        It 'sets $count=true when Count switch is used' {
            $item = New-ptGraphRequestItem -url '/users' -Count
            $item.url | Should -Match '\$count=true'
        }

        It 'preserves existing query and merges additional parameters' {
            $item = New-ptGraphRequestItem -url '/users?$expand=manager' -pageSize 10
            $item.url | Should -Match '\$expand=manager'
            $item.url | Should -Match '\$top=10'
        }

        It 'allows QueryParameters to override existing query values' {
            $item = New-ptGraphRequestItem -url '/users?$top=5' -QueryParameters @{ '$top' = '50'; custom = 'x' }
            $item.url | Should -Match '\$top=50'
            $item.url | Should -Match 'custom=x'
        }

        It 'warns when an OData function param overrides a different value already in the URL' {
            $item = New-ptGraphRequestItem -url '/users?$top=5' -pageSize 10 -WarningVariable warnings 3>$null
            $warnings | Should -Match '\$top'
            $item.url | Should -Match '\$top=10'
        }

        It 'does not warn when the OData function param matches the existing URL value' {
            New-ptGraphRequestItem -url '/users?$top=10' -pageSize 10 -WarningVariable warnings 3>$null | Out-Null
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context 'Headers and body handling' {
        It 'adds ConsistencyLevel header when specified' {
            $item = New-ptGraphRequestItem -url '/users' -ConsistencyLevel eventual
            $item.headers.ConsistencyLevel | Should -Be 'eventual'
        }

        It 'defaults Content-Type to application/json when body is provided' {
            $item = New-ptGraphRequestItem -url '/users' -method POST -body @{ displayName = 'Alice' }
            $item.headers.'Content-Type' | Should -Be 'application/json'
        }

        It 'uses explicit ContentType when provided' {
            $item = New-ptGraphRequestItem -url '/users' -method POST -body 'name=alice' -ContentType 'application/x-www-form-urlencoded'
            $item.headers.'Content-Type' | Should -Be 'application/x-www-form-urlencoded'
        }

        It 'retains hashtable body as hashtable' {
            $body = @{ displayName = 'Alice'; department = 'Sales' }
            $item = New-ptGraphRequestItem -url '/users' -method POST -body $body
            $item.body | Should -BeOfType [hashtable]
            $item.body.displayName | Should -Be 'Alice'
        }

        It 'retains string body as string' {
            $body = '{"displayName":"Alice"}'
            $item = New-ptGraphRequestItem -url '/users' -method POST -body $body
            $item.body | Should -BeOfType [string]
        }

        It 'throws for unsupported body type' {
            { New-ptGraphRequestItem -url '/users' -method POST -body 123 } | Should -Throw
        }

        It 'warns when -ContentType and headers Content-Type differ' {
            $item = New-ptGraphRequestItem -url '/users' -method POST -body '{}' `
                -ContentType 'application/json' -headers @{ 'Content-Type' = 'text/plain' } `
                -WarningVariable warnings 3>$null
            $warnings | Should -Match 'Content-Type'
            $item.headers.'Content-Type' | Should -Be 'application/json'
        }

        It 'does not warn when ContentType matches the Content-Type header' {
            New-ptGraphRequestItem -url '/users' -method POST -body '{}' `
                -ContentType 'application/json' -headers @{ 'Content-Type' = 'application/json' } `
                -WarningVariable warnings 3>$null | Out-Null
            $warnings | Should -BeNullOrEmpty
        }

        It 'warns when a string body is not valid JSON and no ContentType override is set' {
            $item = New-ptGraphRequestItem -url '/users' -method POST -body 'not-valid-json' `
                -WarningVariable warnings 3>$null
            ($warnings -join ' ') | Should -Match 'valid JSON'
            $item.body | Should -Be 'not-valid-json'
        }

        It 'does not warn about invalid JSON when ContentType is set to a non-JSON type' {
            New-ptGraphRequestItem -url '/users' -method POST -body 'key=value' `
                -ContentType 'application/x-www-form-urlencoded' `
                -WarningVariable warnings 3>$null | Out-Null
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context 'Other fields' {
        It 'sets dependsOn when provided' {
            $item = New-ptGraphRequestItem -url '/users' -dependsOn 'request-1'
            $item.dependsOn | Should -Be 'request-1'
        }

        It 'warns when POST is used without body' {
            New-ptGraphRequestItem -url '/users' -method POST -WarningVariable +warnings 3>$null | Out-Null
            ($warnings -join ' ') | Should -Match 'without a body'
        }

        It 'supports legacy bodyHashtable alias' {
            $item = New-ptGraphRequestItem -url '/users' -method POST -bodyHashtable @{ displayName = 'Legacy' }
            $item.body.displayName | Should -Be 'Legacy'
        }

        It 'supports legacy bodyString alias' {
            $item = New-ptGraphRequestItem -url '/users' -method POST -bodyString '{"displayName":"Legacy"}'
            $item.body | Should -BeOfType [string]
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
