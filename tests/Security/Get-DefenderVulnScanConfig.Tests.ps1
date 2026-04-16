Describe 'Get-DefenderVulnScanConfig - MDE Active' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    createdDateTime = (Get-Date).ToString('o')
                    currentScore    = 350
                    maxScore        = 500
                    enabledServices = @('HasMDEP2', 'HasDefender')
                    controlScores   = @()
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderVulnScanConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when MDE is active in enabled services' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-VULNSCAN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-VULNSCAN-001*' }
        $check.CheckId | Should -Match '^DEFENDER-VULNSCAN-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderVulnScanConfig - Score Exists But No MDE' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    createdDateTime = (Get-Date).ToString('o')
                    currentScore    = 100
                    maxScore        = 500
                    enabledServices = @('HasExchange')
                    controlScores   = @()
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderVulnScanConfig.ps1"
    }

    It 'Status is Warning when Secure Score exists but MDE not detected' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-VULNSCAN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderVulnScanConfig - No Score Data' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderVulnScanConfig.ps1"
    }

    It 'Status is Fail when no Secure Score data available' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-VULNSCAN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
