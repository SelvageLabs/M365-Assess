BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Test-ModuleCompatibility' {
    BeforeAll {
        function Get-MgContext { }
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/Test-ModuleCompatibility.ps1"

        Mock Write-Host { }
        Mock Write-AssessmentLog { }

        $sectionServiceMap = @{
            'Identity' = @('Graph')
            'Email'    = @('ExchangeOnline')
            'PowerBI'  = @()
        }
    }

    Context 'when all required modules are installed and compatible' {
        BeforeAll {
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'2.35.0'; ModuleBase = 'C:\fake\graph' }
            } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }

            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'3.7.1'; ModuleBase = 'C:\fake\exo' }
            } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }

            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'7.8.0' }
            } -ParameterFilter { $Name -eq 'ImportExcel' }
        }

        It 'should return Passed = true' {
            $result = Test-ModuleCompatibility -Section @('Identity', 'Email') -SectionServiceMap $sectionServiceMap -NonInteractive
            $result.Passed | Should -Be $true
        }

        It 'should preserve the Section list' {
            $result = Test-ModuleCompatibility -Section @('Identity', 'Email') -SectionServiceMap $sectionServiceMap -NonInteractive
            $result.Section | Should -Contain 'Identity'
            $result.Section | Should -Contain 'Email'
        }
    }

    Context 'when Graph module is missing (NonInteractive)' {
        BeforeAll {
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'3.7.1'; ModuleBase = 'C:\fake\exo' }
            } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Install-Module { }
            Mock Write-Error { }
        }

        It 'should return nothing (fatal)' {
            $result = Test-ModuleCompatibility -Section @('Identity') -SectionServiceMap $sectionServiceMap -NonInteractive
            $result | Should -BeNullOrEmpty
        }

        It 'should write an error' {
            Test-ModuleCompatibility -Section @('Identity') -SectionServiceMap $sectionServiceMap -NonInteractive
            Should -Invoke Write-Error -Times 1
        }
    }

    Context 'when EXO module is missing (NonInteractive)' {
        BeforeAll {
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'2.35.0'; ModuleBase = 'C:\fake\graph' }
            } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Install-Module { }
            Mock Write-Error { }
        }

        It 'should return nothing (fatal)' {
            $result = Test-ModuleCompatibility -Section @('Email') -SectionServiceMap $sectionServiceMap -NonInteractive
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when EXO version has MSAL conflict (>= 3.8.0, NonInteractive)' {
        BeforeAll {
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'2.35.0'; ModuleBase = 'C:\fake\graph' }
            } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'3.8.0'; ModuleBase = 'C:\fake\exo' }
            } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Install-Module { }
            Mock Write-Error { }
        }

        It 'should return nothing (fatal MSAL conflict)' {
            $result = Test-ModuleCompatibility -Section @('Email') -SectionServiceMap $sectionServiceMap -NonInteractive
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when only Graph-using sections are selected and EXO is not needed' {
        BeforeAll {
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'2.35.0'; ModuleBase = 'C:\fake\graph' }
            } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'7.8.0' }
            } -ParameterFilter { $Name -eq 'ImportExcel' }
        }

        It 'should pass without requiring EXO' {
            $result = Test-ModuleCompatibility -Section @('Identity') -SectionServiceMap $sectionServiceMap -NonInteractive
            $result.Passed | Should -Be $true
        }
    }

    Context 'when recommended modules are missing (NonInteractive auto-install)' {
        BeforeAll {
            Mock Get-Module {
                [PSCustomObject]@{ Version = [version]'2.35.0'; ModuleBase = 'C:\fake\graph' }
            } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Install-Module { }
        }

        It 'should auto-install recommended modules' {
            Test-ModuleCompatibility -Section @('Identity', 'PowerBI') -SectionServiceMap $sectionServiceMap -NonInteractive
            Should -Invoke Install-Module -Times 2
        }
    }

    Context 'when no sections need any services' {
        BeforeAll {
            $emptyServiceMap = @{ 'ActiveDirectory' = @() }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'Microsoft.Graph.Authentication' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'MicrosoftPowerBIMgmt' }
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Install-Module { }
        }

        It 'should pass even with no modules installed' {
            $result = Test-ModuleCompatibility -Section @('ActiveDirectory') -SectionServiceMap $emptyServiceMap -NonInteractive
            # ImportExcel will be flagged as recommended but auto-installed; result should still pass
            $result.Passed | Should -Be $true
        }
    }
}
