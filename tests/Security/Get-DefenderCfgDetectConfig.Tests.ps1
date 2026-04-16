Describe 'Get-DefenderCfgDetectConfig - Active Device Controls' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    title           = 'Enable device discovery'
                    controlCategory = 'Device'
                    controlStateUpdates = @(
                        @{ state = 'thirdParty'; updatedDateTime = (Get-Date).ToString('o') }
                    )
                }
                @{
                    title           = 'Review unauthorized device configurations'
                    controlCategory = 'Device'
                    controlStateUpdates = @(
                        @{ state = 'resolved'; updatedDateTime = (Get-Date).ToString('o') }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderCfgDetectConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when device config controls are actively configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-CFGDETECT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-CFGDETECT-001*' }
        $check.CheckId | Should -Match '^DEFENDER-CFGDETECT-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderCfgDetectConfig - Controls Tracked But Default State' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    title           = 'Enable device discovery'
                    controlCategory = 'Device'
                    controlStateUpdates = @(
                        @{ state = 'Default'; updatedDateTime = (Get-Date).ToString('o') }
                    )
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderCfgDetectConfig.ps1"
    }

    It 'Status is Fail when device controls exist but none are actively configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-CFGDETECT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderCfgDetectConfig - No Control Profiles' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderCfgDetectConfig.ps1"
    }

    It 'Status is Fail when no control profiles returned' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-CFGDETECT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
