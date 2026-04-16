Describe 'Get-EntraTouConfig - Agreement Required' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ id = 'agree-1'; displayName = 'CUI Acceptable Use'; isViewingBeforeAcceptanceRequired = $true }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraTouConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'Status is Pass when acceptance is required before viewing' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-TOU-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'CheckId follows naming convention' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-TOU-001*' }
        $check.CheckId | Should -Match '^ENTRA-TOU-001\.\d+$'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-EntraTouConfig - Agreement Exists But Not Required' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @(
                @{ id = 'agree-1'; displayName = 'ToU'; isViewingBeforeAcceptanceRequired = $false }
            ) }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraTouConfig.ps1"
    }

    It 'Status is Warning when agreement exists but acceptance not required' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-TOU-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Warning'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}

Describe 'Get-EntraTouConfig - No Agreements' {
    BeforeAll {
        function global:Update-CheckProgress { param($CheckId, $Setting, $Status) }

        Mock Invoke-MgGraphRequest {
            return @{ value = @() }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-EntraTouConfig.ps1"
    }

    It 'Status is Fail when no agreements exist' {
        $check = $settings | Where-Object { $_.CheckId -like 'ENTRA-TOU-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Fail'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
