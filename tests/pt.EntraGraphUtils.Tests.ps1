BeforeAll {
    $RepoRoot   = Split-Path $PSScriptRoot -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psd1") -Force
}

Describe 'Module — load and exports' {
    BeforeDiscovery {
        $RepoRoot   = Split-Path $PSScriptRoot -Parent
        $SrcRoot    = Join-Path $RepoRoot 'src'
        $script:PublicNames  = Get-ChildItem (Join-Path $SrcRoot 'public')  -Filter *.ps1 | Select-Object -ExpandProperty BaseName
        $script:PrivateNames = Get-ChildItem (Join-Path $SrcRoot 'private') -Filter *.ps1 | Select-Object -ExpandProperty BaseName
    }

    It 'module is loaded after import' {
        Get-Module $ModuleName | Should -Not -BeNullOrEmpty
    }

    It 'exports <_>' -ForEach $script:PublicNames {
        Get-Command -Module $ModuleName -Name $_ | Should -Not -BeNullOrEmpty
    }

    It 'does NOT export <_>' -ForEach $script:PrivateNames {
        Get-Command -Module $ModuleName -Name $_ -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Help documentation' {
    BeforeDiscovery {
        $RepoRoot   = Split-Path $PSScriptRoot -Parent
        $SrcRoot    = Join-Path $RepoRoot 'src'
        $script:HelpTestCases = Get-ChildItem (Join-Path $SrcRoot 'public') -Filter *.ps1 |
            ForEach-Object { @{ CommandName = $_.BaseName } }
    }

    Context '<CommandName> synopsis' -ForEach $script:HelpTestCases {
        It 'has a non-empty synopsis' {
            (Get-Help $CommandName).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has at least one example' {
            (Get-Help $CommandName).Examples.Example | Should -Not -BeNullOrEmpty
        }

        It 'every parameter has a description' {
            $help = Get-Help $CommandName -Full
            $params = $help.Parameters.Parameter | Where-Object { $_.Name -notmatch '^(WhatIf|Confirm|Verbose|Debug|ErrorAction|WarningAction|InformationAction|ErrorVariable|WarningVariable|InformationVariable|OutVariable|OutBuffer|PipelineVariable)$' }
            foreach ($p in $params) {
                $p.Description.Text | Should -Not -BeNullOrEmpty -Because "parameter -$($p.Name) needs a description"
            }
        }
    }
}

Describe 'Public function file conventions' {
    BeforeDiscovery {
        $RepoRoot   = Split-Path $PSScriptRoot -Parent
        $SrcRoot    = Join-Path $RepoRoot 'src'
        $script:PublicFiles = Get-ChildItem (Join-Path $SrcRoot 'public') -Filter *.ps1 | Sort-Object Name
    }

    Context '<_.Name>' -ForEach $script:PublicFiles {
        It 'contains exactly one top-level function' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName, [ref]$null, [ref]$null
            )
            $functions = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $false  # do not recurse into nested script blocks — top-level only
            )
            $functions.Count | Should -Be 1 -Because "each public file must define exactly one function"
        }

        It 'function name matches file name' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName, [ref]$null, [ref]$null
            )
            $functions = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $false
            )
            $functions[0].Name | Should -Be $_.BaseName -Because "file name drives Export-ModuleMember"
        }
    }
}

Describe 'Help URI' -Skip:(-not $env:MYMODULE_PATH) {
    BeforeDiscovery {
        $RepoRoot = Split-Path $PSScriptRoot -Parent
        $SrcRoot  = Join-Path $RepoRoot 'src'
        $script:HelpUriCases = Get-ChildItem (Join-Path $SrcRoot 'public') -Filter *.ps1 |
            ForEach-Object { @{ CommandName = $_.BaseName } }
    }

    It '<CommandName> has HelpUri set' -ForEach $script:HelpUriCases {
        (Get-Command -Module $ModuleName -Name $CommandName).HelpUri | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test file coverage' {
    BeforeDiscovery {
        $RepoRoot   = Split-Path $PSScriptRoot -Parent
        $SrcRoot    = Join-Path $RepoRoot 'src'
        $script:SourceFiles = @(
            Get-ChildItem (Join-Path $SrcRoot 'public')  -Filter *.ps1 | ForEach-Object { @{ File = $_; Subfolder = 'public'  } }
            Get-ChildItem (Join-Path $SrcRoot 'private') -Filter *.ps1 | ForEach-Object { @{ File = $_; Subfolder = 'private' } }
        ) | Sort-Object { $_.File.Name }
    }

    Context '<File.BaseName> (<Subfolder>)' -ForEach $script:SourceFiles {
        It 'has a matching test file in tests/<Subfolder>/' {
            $expected = Join-Path $PSScriptRoot "$Subfolder/$($File.BaseName).Tests.ps1"
            $expected | Should -Exist -Because "every source file should have a Pester test file"
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
