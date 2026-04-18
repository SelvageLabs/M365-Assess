Describe 'Get-IntuneMobileEncryptConfig - Both platforms encrypted' {
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

    It 'Returns two settings rows' {
        $settings.Count | Should -Be 2
    }

    It 'iOS policy row is Pass' {
        $row = $settings | Where-Object { $_.Setting -match 'iOS' }
        $row | Should -Not -BeNullOrEmpty
        $row.Status | Should -Be 'Pass'
    }

    It 'Android policy row is Pass' {
        $row = $settings | Where-Object { $_.Setting -match 'Android' }
        $row | Should -Not -BeNullOrEmpty
        $row.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $settings | ForEach-Object { $_.CheckId | Should -Match '^INTUNE-MOBILEENCRYPT-001\.\d+$' }
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneMobileEncryptConfig - Only iOS encrypted' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ '@odata.type' = '#microsoft.graph.iosCompliancePolicy'; storageRequireEncryption = $true; displayName = 'iOS Policy' }
                @{ '@odata.type' = '#microsoft.graph.androidCompliancePolicy'; storageRequireEncryption = $false; displayName = 'Android Policy' }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneMobileEncryptConfig.ps1"
    }

    It 'iOS policy row is Pass' {
        ($settings | Where-Object { $_.Setting -match 'iOS' }).Status | Should -Be 'Pass'
    }

    It 'Android policy row is Fail' {
        ($settings | Where-Object { $_.Setting -match 'Android' }).Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneMobileEncryptConfig - No policies' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest { return @{ value = @() } }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneMobileEncryptConfig.ps1"
    }

    It 'Emits sentinel rows for both missing platforms' {
        $settings.Count | Should -Be 2
    }

    It 'Both sentinel rows are Fail' {
        $settings | ForEach-Object { $_.Status | Should -Be 'Fail' }
    }

    It 'iOS sentinel CurrentValue mentions no policy found' {
        ($settings | Where-Object { $_.Setting -match 'iOS' }).CurrentValue | Should -Match 'No iOS compliance policy found'
    }

    It 'Android sentinel CurrentValue mentions no policy found' {
        ($settings | Where-Object { $_.Setting -match 'Android' }).CurrentValue | Should -Match 'No Android compliance policy found'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
