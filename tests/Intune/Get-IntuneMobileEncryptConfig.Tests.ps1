Describe 'Get-IntuneMobileEncryptConfig - Both Platforms Encrypted' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ '@odata.type' = '#microsoft.graph.iosCompliancePolicy'; storageRequireEncryption = $true; displayName = 'iOS Policy' }
                @{ '@odata.type' = '#microsoft.graph.androidCompliancePolicy'; storageRequireEncryption = $true; displayName = 'Android Policy' }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneMobileEncryptConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when both iOS and Android require encryption' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-MOBILEENCRYPT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-MOBILEENCRYPT-001*' }
        $check.CheckId | Should -Match '^INTUNE-MOBILEENCRYPT-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneMobileEncryptConfig - Only iOS Encrypted' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ '@odata.type' = '#microsoft.graph.iosCompliancePolicy'; storageRequireEncryption = $true }
                @{ '@odata.type' = '#microsoft.graph.androidCompliancePolicy'; storageRequireEncryption = $false }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneMobileEncryptConfig.ps1"
    }

    It 'Status is Warning when only one platform is covered' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-MOBILEENCRYPT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneMobileEncryptConfig - No Encryption' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneMobileEncryptConfig.ps1"
    }

    It 'Status is Fail when no encryption policies exist' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-MOBILEENCRYPT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
