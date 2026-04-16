Describe 'Get-IntuneInventoryConfig - Devices and Categories' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'managedDeviceOverview') {
                return @{ enrolledDeviceCount = 42 }
            }
            if ($Uri -match 'deviceCategories') {
                return @{ value = @(
                    @{ id = 'cat-1'; displayName = 'Workstations' }
                    @{ id = 'cat-2'; displayName = 'Servers' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneInventoryConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when enrolled devices and categories both exist' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-INVENTORY-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-INVENTORY-001*' }
        $check.CheckId | Should -Match '^INTUNE-INVENTORY-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneInventoryConfig - Devices But No Categories' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'managedDeviceOverview') {
                return @{ enrolledDeviceCount = 10 }
            }
            if ($Uri -match 'deviceCategories') {
                return @{ value = @() }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneInventoryConfig.ps1"
    }

    It 'Status is Warning when devices enrolled but no categories configured' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-INVENTORY-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IntuneInventoryConfig - No Devices' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            if ($Uri -match 'managedDeviceOverview') {
                return @{ enrolledDeviceCount = 0 }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Intune/Get-IntuneInventoryConfig.ps1"
    }

    It 'Status is Fail when no devices enrolled' {
        $check = $settings | Where-Object { $_.CheckId -like 'INTUNE-INVENTORY-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
