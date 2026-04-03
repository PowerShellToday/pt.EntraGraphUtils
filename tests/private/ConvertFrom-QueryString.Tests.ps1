BeforeAll {
    $RepoRoot   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }

    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psm1") -Force
}

Describe 'ConvertFrom-QueryString (private)' {
    Context 'Basic conversion' {
        It 'converts query string to object properties' {
            InModuleScope $ModuleName {
                $result = ConvertFrom-QueryString '?name=alice&index=10'
                $result.name | Should -Be 'alice'
                $result.index | Should -Be '10'
            }
        }

        It 'supports pipeline input' {
            InModuleScope $ModuleName {
                $result = 'name=bob&active=true' | ConvertFrom-QueryString
                $result.name | Should -Be 'bob'
                $result.active | Should -Be 'true'
            }
        }

        It 'returns hashtable when AsHashtable is used' {
            InModuleScope $ModuleName {
                $result = ConvertFrom-QueryString 'name=carol&role=admin' -AsHashtable
                $result | Should -BeOfType [hashtable]
                $result['name'] | Should -Be 'carol'
                $result['role'] | Should -Be 'admin'
            }
        }
    }

    Context 'Decoding behavior' {
        It 'decodes parameter names when DecodeParameterNames is set' {
            InModuleScope $ModuleName {
                $result = ConvertFrom-QueryString 'display%20name=Alice%20A' -DecodeParameterNames -AsHashtable
                $result.ContainsKey('display name') | Should -BeTrue
                $result['display name'] | Should -Be 'Alice A'
            }
        }

        It 'always URL-decodes parameter values' {
            InModuleScope $ModuleName {
                $result = ConvertFrom-QueryString 'city=New%20York&symbol=%26' -AsHashtable
                $result['city'] | Should -Be 'New York'
                $result['symbol'] | Should -Be '&'
            }
        }
    }

    Context 'Multiple input strings' {
        It 'outputs one object per input query string' {
            InModuleScope $ModuleName {
                $result = ConvertFrom-QueryString @('id=1', 'id=2') -AsHashtable
                $result.Count | Should -Be 2
                $result[0]['id'] | Should -Be '1'
                $result[1]['id'] | Should -Be '2'
            }
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
