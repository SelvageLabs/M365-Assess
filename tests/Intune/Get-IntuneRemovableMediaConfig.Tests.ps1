Describe 'Get-IntuneRemovableMediaConfig - Block profile assigned' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        '@odata.type'                = '#microsoft.graph.windows10GeneralConfiguration'
                        displayName                  = 'CMMC Removable Media Block'
                        storageBlockRemovableStorage = $true
                        assignments                  = @(@{ id = 'assign-001'; target = @{ groupId = 'grp-001' } })
                    }
                )
            }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneRemovableMediaConfig.ps1"
    }

    It 'Returns one row for the blocking profile' {
        $settings.Count | Should -Be 1
    }

    It 'Status is Pass when block profile is assigned' {
        $settings[0].Status | Should -Be 'Pass'
    }

    It 'Setting includes the profile name' {
        $settings[0].Setting | Should -Match 'CMMC Removable Media Block'
    }

    It 'CurrentValue mentions assignment count' {
        $settings[0].CurrentValue | Should -Match '1 assignment'
    }

    It 'CheckId follows naming convention' {
        $settings[0].CheckId | Should -Match '^INTUNE-REMOVABLEMEDIA-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneRemovableMediaConfig - Block profile not assigned' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        '@odata.type'                = '#microsoft.graph.windows10GeneralConfiguration'
                        displayName                  = 'Unassigned Block Policy'
                        storageBlockRemovableStorage = $true
                        assignments                  = @()
                    }
                )
            }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneRemovableMediaConfig.ps1"
    }

    It 'Status is Fail when block profile has no assignments' {
        $settings[0].Status | Should -Be 'Fail'
    }

    It 'CurrentValue mentions no active assignments' {
        $settings[0].CurrentValue | Should -Match 'no active assignments'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneRemovableMediaConfig - Multiple profiles mixed assignment' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{
                value = @(
                    @{
                        '@odata.type'                = '#microsoft.graph.windows10GeneralConfiguration'
                        displayName                  = 'Assigned Block'
                        storageBlockRemovableStorage = $true
                        assignments                  = @(@{ id = 'a1' })
                    }
                    @{
                        '@odata.type'                = '#microsoft.graph.windows10GeneralConfiguration'
                        displayName                  = 'Unassigned Block'
                        storageBlockRemovableStorage = $true
                        assignments                  = @()
                    }
                )
            }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneRemovableMediaConfig.ps1"
    }

    It 'Returns one row per blocking profile' {
        $settings.Count | Should -Be 2
    }

    It 'Assigned profile is Pass' {
        ($settings | Where-Object { $_.Setting -match '— Assigned Block$' }).Status | Should -Be 'Pass'
    }

    It 'Unassigned profile is Fail' {
        ($settings | Where-Object { $_.Setting -match '— Unassigned Block$' }).Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneRemovableMediaConfig - No block profile' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest { return @{ value = @() } }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneRemovableMediaConfig.ps1"
    }

    It 'Emits one Fail sentinel row' {
        $settings.Count | Should -Be 1
        $settings[0].Status | Should -Be 'Fail'
    }

    It 'CurrentValue mentions no profile found' {
        $settings[0].CurrentValue | Should -Match 'No removable storage block profile found'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneRemovableMediaConfig - Forbidden' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest { throw '403 Forbidden - Authorization_RequestDenied' }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneRemovableMediaConfig.ps1"
    }

    It 'Status is Review when Graph returns 403' {
        $settings[0].Status | Should -Be 'Review'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
