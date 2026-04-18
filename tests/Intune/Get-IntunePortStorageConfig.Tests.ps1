Describe 'Get-IntunePortStorageConfig - Profile with USB blocked' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'; displayName = 'Device Restrictions'; usbBlocked = $true; storageBlockRemovableStorage = $false }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntunePortStorageConfig.ps1"
    }

    It 'Returns one row per profile' {
        $settings.Count | Should -Be 1
    }

    It 'Status is Pass when USB is blocked' {
        $settings[0].Status | Should -Be 'Pass'
    }

    It 'CurrentValue includes USB blocked' {
        $settings[0].CurrentValue | Should -Match 'USB blocked'
    }

    It 'Setting includes profile name' {
        $settings[0].Setting | Should -Match 'Device Restrictions'
    }

    It 'CheckId follows naming convention' {
        $settings[0].CheckId | Should -Match '^INTUNE-PORTSTORAGE-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntunePortStorageConfig - Mixed profiles' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'; displayName = 'Locked Profile'; usbBlocked = $true; storageBlockRemovableStorage = $true }
                @{ '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'; displayName = 'Open Profile'; usbBlocked = $false; storageBlockRemovableStorage = $false }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntunePortStorageConfig.ps1"
    }

    It 'Returns one row per profile' {
        $settings.Count | Should -Be 2
    }

    It 'Locked profile is Pass' {
        ($settings | Where-Object { $_.Setting -match 'Locked' }).Status | Should -Be 'Pass'
    }

    It 'Open profile is Fail' {
        ($settings | Where-Object { $_.Setting -match 'Open' }).Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntunePortStorageConfig - No Windows profiles' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest { return @{ value = @() } }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntunePortStorageConfig.ps1"
    }

    It 'Emits one Fail sentinel row' {
        $settings.Count | Should -Be 1
        $settings[0].Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
