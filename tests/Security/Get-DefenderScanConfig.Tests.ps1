Describe 'Get-DefenderScanConfig - Real-time Protection Enabled' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'deviceConfigurations') {
                return @{ value = @(
                    @{
                        '@odata.type'               = '#microsoft.graph.windows10GeneralConfiguration'
                        displayName                 = 'Defender AV Policy'
                        defenderMonitorFileActivity = 'monitorAllFiles'
                        defenderRealtimeScanDirection = $null
                    }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderScanConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when real-time scanning is configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-REALTIMESCAN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-REALTIMESCAN-001*' }
        $check.CheckId | Should -Match '^DEFENDER-REALTIMESCAN-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderScanConfig - Antivirus Intent Policy' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'deviceConfigurations') {
                return @{ value = @() }
            }
            if ($Uri -match 'intents') {
                return @{ value = @(
                    @{ templateId = 'antivirus-template-id'; displayName = 'Defender Antivirus' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderScanConfig.ps1"
    }

    It 'Status is Pass when endpoint security antivirus intent is deployed' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-REALTIMESCAN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DefenderScanConfig - Not Configured' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Security/Get-DefenderScanConfig.ps1"
    }

    It 'Status is Fail when no real-time protection policy found' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-REALTIMESCAN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
