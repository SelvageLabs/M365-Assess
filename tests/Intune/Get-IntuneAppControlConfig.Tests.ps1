Describe 'Get-IntuneAppControlConfig - AppLocker Policy Present' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type'                = '#microsoft.graph.windows10EndpointProtectionConfiguration'
                    displayName                  = 'Endpoint Protection'
                    appLockerApplicationControl  = 'enforceComponentsStoreAppsAndSmartlocker'
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAppControlConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when AppLocker policy is configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-APPCONTROL-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-APPCONTROL-001*' }
        $check.CheckId | Should -Match '^INTUNE-APPCONTROL-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneAppControlConfig - WDAC via OMA-URI' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName   = 'WDAC Policy'
                    omaSettings   = @(
                        @{ omaUri = './Device/Vendor/MSFT/Policy/Config/ApplicationControl'; value = '<WDAC Policy XML>' }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAppControlConfig.ps1"
    }

    It 'Status is Pass when WDAC OMA-URI policy is configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-APPCONTROL-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneAppControlConfig - No Policy' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAppControlConfig.ps1"
    }

    It 'Status is Fail when no application control policies found' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-APPCONTROL-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
