BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModuleName = Split-Path $RepoRoot -Leaf
    $ModuleRoot = if ($env:MYMODULE_PATH) { $env:MYMODULE_PATH } else { Join-Path $RepoRoot 'src' }

    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot "$ModuleName.psm1") -Force
}

Describe 'Write-Log (private)' {
    Context 'Parameter validation' {
        It 'Message is mandatory' {
            InModuleScope $ModuleName {
                $command = Get-Command -Name Write-Log
                $messageParameter = $command.Parameters['Message']
                $parameterAttribute = $messageParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1

                $parameterAttribute.Mandatory | Should -BeTrue
            }
        }

        It 'Level defaults to Info' {
            InModuleScope $ModuleName {
                Mock Write-Host {}
                Write-Log -Message 'hello'
                Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
                    $Object -eq 'hello'
                }
            }
        }
    }

    Context 'Level routing' {
        It 'routes Verbose level to Write-Verbose' {
            InModuleScope $ModuleName {
                Mock Write-Verbose {}
                Write-Log -Message 'v' -Level Verbose -Verbose
                Should -Invoke Write-Verbose -Times 1 -Exactly -ParameterFilter {
                    $Message -eq 'v'
                }
            }
        }

        It 'routes Info level to Write-Host' {
            InModuleScope $ModuleName {
                Mock Write-Host {}
                Write-Log -Message 'i' -Level Info
                Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
                    $Object -eq 'i'
                }
            }
        }

        It 'routes Warning level to Write-Warning' {
            InModuleScope $ModuleName {
                Mock Write-Warning {}
                Write-Log -Message 'w' -Level Warning
                Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
                    $Message -eq 'w'
                }
            }
        }

        It 'routes Error level to Write-Error' {
            InModuleScope $ModuleName {
                Mock Write-Error {}
                Write-Log -Message 'e' -Level Error -ErrorAction SilentlyContinue
                Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                    $Message -eq 'e'
                }
            }
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
}
