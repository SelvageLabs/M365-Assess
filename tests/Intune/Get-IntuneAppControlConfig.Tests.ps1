Describe 'Get-IntuneAppControlConfig - AppLocker via endpoint protection' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ '@odata.type' = '#microsoft.graph.windows10EndpointProtectionConfiguration'; displayName = 'CMMC AppControl'; appLockerApplicationControl = 'enforceComponentsAndStoreApps' }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAppControlConfig.ps1"
    }

    It 'Returns one row for the matching profile' {
        $settings.Count | Should -Be 1
    }

    It 'Status is Pass' {
        $settings[0].Status | Should -Be 'Pass'
    }

    It 'Setting includes profile name' {
        $settings[0].Setting | Should -Match 'CMMC AppControl'
    }

    It 'CurrentValue includes AppLocker mode' {
        $settings[0].CurrentValue | Should -Match 'enforceComponentsAndStoreApps'
    }

    It 'CheckId follows naming convention' {
        $settings[0].CheckId | Should -Match '^INTUNE-APPCONTROL-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneAppControlConfig - WDAC via custom OMA-URI' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName   = 'WDAC Policy'
                    omaSettings   = @(
                        @{ omaUri = './Vendor/MSFT/ApplicationControl/Policies/12345'; value = '<SiPolicy/>' }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAppControlConfig.ps1"
    }

    It 'Status is Pass' {
        $settings[0].Status | Should -Be 'Pass'
    }

    It 'Setting includes profile name' {
        $settings[0].Setting | Should -Match 'WDAC Policy'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneAppControlConfig - No app control policies' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest { return @{ value = @() } }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAppControlConfig.ps1"
    }

    It 'Emits one Fail sentinel row' {
        $settings.Count | Should -Be 1
        $settings[0].Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
