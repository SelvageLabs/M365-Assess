Describe 'Get-IntunePortStorageConfig - Storage Blocked' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{
                    '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                    displayName   = 'Win10 Restrictions'
                    usbBlocked    = $true
                    storageBlockRemovableStorage = $true
                }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntunePortStorageConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when removable storage is blocked' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-PORTSTORAGE-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-PORTSTORAGE-001*' }
        $check.CheckId | Should -Match '^INTUNE-PORTSTORAGE-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntunePortStorageConfig - No Restrictions' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntunePortStorageConfig.ps1"
    }

    It 'Status is Fail when no restriction policies found' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-PORTSTORAGE-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
