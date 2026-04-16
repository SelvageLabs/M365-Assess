Describe 'Get-IntuneAutoDiscConfig - MDM Auto-Enrollment Configured' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'deviceEnrollmentConfigurations') {
                return @{ value = @(
                    @{ '@odata.type' = '#microsoft.graph.deviceEnrollmentWindowsAutoEnrollment'; displayName = 'Windows MDM Auto Enrollment' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAutoDiscConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when MDM auto-enrollment is configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-AUTODISC-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-AUTODISC-001*' }
        $check.CheckId | Should -Match '^INTUNE-AUTODISC-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneAutoDiscConfig - Autopilot Profile Configured' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'deviceEnrollmentConfigurations') {
                return @{ value = @(
                    @{ '@odata.type' = '#microsoft.graph.windowsAutopilotDeploymentProfile'; displayName = 'Autopilot Profile' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAutoDiscConfig.ps1"
    }

    It 'Status is Pass when Autopilot profile is configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-AUTODISC-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneAutoDiscConfig - No Auto-Enrollment' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneAutoDiscConfig.ps1"
    }

    It 'Status is Warning when no auto-enrollment detected (manual may be in use)' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-AUTODISC-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
