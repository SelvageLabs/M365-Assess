Describe 'Get-IntuneFipsConfig - FIPS Enabled via OMA-URI' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName   = 'FIPS Policy'
                    omaSettings   = @(
                        @{ omaUri = './Device/Vendor/MSFT/Policy/Config/Cryptography/AllowFipsAlgorithmPolicy'; value = 1 }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneFipsConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when FIPS OMA-URI is set to 1' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-FIPS-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-FIPS-001*' }
        $check.CheckId | Should -Match '^INTUNE-FIPS-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneFipsConfig - FIPS Policy Name Match (Warning)' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10EndpointProtectionConfiguration'
                    displayName   = 'FIPS Cryptography Settings'
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneFipsConfig.ps1"
    }

    It 'Status is Warning when a FIPS-named policy is found but OMA-URI not confirmed' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-FIPS-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneFipsConfig - Not Configured' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneFipsConfig.ps1"
    }

    It 'Status is Fail when no FIPS policy exists' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-FIPS-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
