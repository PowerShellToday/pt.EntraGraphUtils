BeforeAll {
    $RepoRoot   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }

    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psm1") -Force
}

Describe 'ConvertTo-QueryString (private)' {
    Context 'Hashtable and dictionary conversion' {
        It 'converts hashtable to query string' {
            InModuleScope $ModuleName {
                $result = ConvertTo-QueryString @{ name = 'alice'; index = 10 }
                $result | Should -Match 'name=alice'
                $result | Should -Match 'index=10'
            }
        }

        It 'URL-encodes parameter values' {
            InModuleScope $ModuleName {
                $result = ConvertTo-QueryString @{ city = 'New York'; symbol = '&' }
                $result | Should -Match 'city=New\+York'
                $result | Should -Match 'symbol=%26'
            }
        }

        It 'supports ordered dictionary input' {
            InModuleScope $ModuleName {
                $input = [ordered]@{ first = '1'; second = '2' }
                $result = ConvertTo-QueryString $input
                $result | Should -Be 'first=1&second=2'
            }
        }

        It 'encodes parameter names when EncodeParameterNames is specified' {
            InModuleScope $ModuleName {
                $result = ConvertTo-QueryString @{ 'display name' = 'Alice' } -EncodeParameterNames
                $result | Should -Match 'display\+name=Alice'
            }
        }
    }

    Context 'Object property conversion' {
        It 'converts object properties to query string' {
            InModuleScope $ModuleName {
                $obj = [PSCustomObject]@{ name = 'bob'; active = $true }
                $result = ConvertTo-QueryString $obj
                $result | Should -Match 'name=bob'
                $result | Should -Match 'active=True'
            }
        }
    }

    Context 'Unsupported input handling' {
        It 'writes a non-terminating error for unsupported input type' {
            InModuleScope $ModuleName {
                $error.Clear()
                $result = ConvertTo-QueryString 123 -ErrorAction SilentlyContinue -ErrorVariable +errVar
                $result | Should -BeNullOrEmpty
                $errVar | Should -Not -BeNullOrEmpty
                $errVar[0].FullyQualifiedErrorId | Should -Match 'ConvertQueryStringFailureTypeNotSupported'
            }
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
