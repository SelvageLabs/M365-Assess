BeforeAll {
    . "$PSScriptRoot/../../src/M365-Assess/Common/SecurityConfigHelper.ps1"
}

Describe 'Add-SecuritySetting - remediation fallback' {
    BeforeEach {
        $ctx = Initialize-SecurityConfig
        $global:M365AssessRegistry = @{
            'ENTRA-MFA-001' = [PSCustomObject]@{ remediation = 'Registry remediation text' }
        }
    }
    AfterEach {
        Remove-Variable -Name M365AssessRegistry -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Uses hardcoded Remediation when provided' {
        Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
            -Category 'MFA' -Setting 'MFA Policy' -CurrentValue 'Enabled' `
            -RecommendedValue 'Enabled' -Status 'Pass' `
            -CheckId 'ENTRA-MFA-001' -Remediation 'Hardcoded text'
        $ctx.Settings[0].Remediation | Should -Be 'Hardcoded text'
    }

    It 'Falls back to registry remediation when Remediation param is empty' {
        Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
            -Category 'MFA' -Setting 'MFA Policy' -CurrentValue 'Enabled' `
            -RecommendedValue 'Enabled' -Status 'Pass' `
            -CheckId 'ENTRA-MFA-001' -Remediation ''
        $ctx.Settings[0].Remediation | Should -Be 'Registry remediation text'
    }

    It 'Leaves Remediation empty when param is empty and CheckId has no registry entry' {
        Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
            -Category 'MFA' -Setting 'Unknown Check' -CurrentValue 'x' `
            -RecommendedValue 'x' -Status 'Info' `
            -CheckId 'UNKNOWN-001' -Remediation ''
        $ctx.Settings[0].Remediation | Should -Be ''
    }
}

Describe 'Add-SecuritySetting - status taxonomy (#774)' {
    BeforeEach {
        $ctx = Initialize-SecurityConfig
    }

    It 'Accepts <Status> as a valid status value' -ForEach @(
        @{ Status = 'Pass' }
        @{ Status = 'Fail' }
        @{ Status = 'Warning' }
        @{ Status = 'Review' }
        @{ Status = 'Info' }
        @{ Status = 'Skipped' }
        @{ Status = 'Unknown' }
        @{ Status = 'NotApplicable' }
        @{ Status = 'NotLicensed' }
    ) {
        {
            Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
                -Category 'Test' -Setting "Status $Status" -CurrentValue 'x' `
                -RecommendedValue 'y' -Status $Status -CheckId 'TEST-001'
        } | Should -Not -Throw

        $ctx.Settings[-1].Status | Should -Be $Status
    }

    It 'Rejects an invalid status value' {
        {
            Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
                -Category 'Test' -Setting 'Invalid' -CurrentValue 'x' `
                -RecommendedValue 'y' -Status 'BananaPancakes' -CheckId 'TEST-001'
        } | Should -Throw -ExpectedMessage '*BananaPancakes*'
    }
}
