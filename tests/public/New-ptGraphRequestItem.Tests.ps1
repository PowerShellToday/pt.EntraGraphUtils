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
