Describe 'Get-DefenderSecureMonConfig - Recent Score' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            # Score updated today — within 7-day window
            return @{ value = @(
                @{
                    createdDateTime = (Get-Date).ToString('o')
                    currentScore    = 300
                    maxScore        = 500
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderSecureMonConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when Secure Score was updated within 7 days' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-SECUREMON-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-SECUREMON-001*' }
        $check.CheckId | Should -Match '^DEFENDER-SECUREMON-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderSecureMonConfig - Stale Score' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            # Score last updated 30 days ago
            return @{ value = @(
                @{
                    createdDateTime = (Get-Date).AddDays(-30).ToString('o')
                    currentScore    = 200
                    maxScore        = 500
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderSecureMonConfig.ps1"
    }

    It 'Status is Warning when Secure Score exists but was not updated recently' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-SECUREMON-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderSecureMonConfig - No Score' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderSecureMonConfig.ps1"
    }

    It 'Status is Fail when no Secure Score data available' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-SECUREMON-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
