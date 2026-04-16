Describe 'Get-EntraSoDConfig - Separated Roles' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            # Two distinct Global Admins
            if ($Uri -match 'roleDefinitionId eq .62e90394') {
                return @{ value = @(
                    @{ principalId = 'user-aa' }
                    @{ principalId = 'user-bb' }
                ) }
            }
            # One Priv Role Admin (different user)
            if ($Uri -match 'roleDefinitionId eq .e8611ab8') {
                return @{ value = @(
                    @{ principalId = 'user-cc' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraSoDConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'Status is Pass when roles are separated' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-SOD-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-SOD-001*' }
        $check.CheckId | Should -Match '^ENTRA-SOD-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-EntraSoDConfig - Overlapping Roles' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            # Same single user holds both roles
            if ($Uri -match 'roleDefinitionId eq') {
                return @{ value = @(
                    @{ principalId = 'user-aa' }
                ) }
            }
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraSoDConfig.ps1"
    }

    It 'Status is Fail when a single user holds both roles' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-SOD-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
