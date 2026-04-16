Describe 'Get-EntraPrivRemoteConfig - PIM Active' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'roleAssignments') {
                # 1 permanent (break-glass only)
                return @{ value = @( @{ principalId = 'bg-user' } ) }
            }
            if ($Uri -match 'roleEligibilityScheduleInstances') {
                # PIM eligible assignments exist
                return @{ value = @(
                    @{ principalId = 'user-a' }
                    @{ principalId = 'user-b' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraPrivRemoteConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when PIM enabled and only break-glass permanent assignments' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-PRIVREMOTE-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-PRIVREMOTE-001*' }
        $check.CheckId | Should -Match '^ENTRA-PRIVREMOTE-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-EntraPrivRemoteConfig - No PIM' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'roleAssignments') {
                return @{ value = @(
                    @{ principalId = 'user-a' }
                    @{ principalId = 'user-b' }
                    @{ principalId = 'user-c' }
                ) }
            }
            if ($Uri -match 'roleEligibilityScheduleInstances') {
                return @{ value = @() }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraPrivRemoteConfig.ps1"
    }

    It 'Status is Fail when no PIM eligible assignments exist' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-PRIVREMOTE-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
