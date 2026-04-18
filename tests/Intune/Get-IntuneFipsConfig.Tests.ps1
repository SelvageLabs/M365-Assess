Describe 'Get-IntuneFipsConfig - FIPS enabled via OMA-URI' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName   = 'FIPS Cryptography Policy'
                    omaSettings   = @(
                        @{ omaUri = './Device/Vendor/MSFT/Policy/Config/Cryptography/AllowFipsAlgorithmPolicy'; value = 1 }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneFipsConfig.ps1"
    }

    It 'Returns one row for the matching profile' {
        $settings.Count | Should -Be 1
    }

    It 'Status is Pass' {
        $settings[0].Status | Should -Be 'Pass'
    }

    It 'Setting includes profile name' {
        $settings[0].Setting | Should -Match 'FIPS Cryptography Policy'
    }

    It 'CurrentValue shows OMA-URI value' {
        $settings[0].CurrentValue | Should -Match 'AllowFipsAlgorithmPolicy'
    }

    It 'CheckId follows naming convention' {
        $settings[0].CheckId | Should -Match '^INTUNE-FIPS-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneFipsConfig - FIPS OMA-URI present but disabled' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName   = 'FIPS Policy Disabled'
                    omaSettings   = @(
                        @{ omaUri = './Device/Vendor/MSFT/Policy/Config/Cryptography/AllowFipsAlgorithmPolicy'; value = 0 }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneFipsConfig.ps1"
    }

    It 'Status is Fail when FIPS value is 0' {
        $settings[0].Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneFipsConfig - No FIPS configuration' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest { return @{ value = @() } }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneFipsConfig.ps1"
    }

    It 'Emits one Fail sentinel row' {
        $settings.Count | Should -Be 1
        $settings[0].Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
