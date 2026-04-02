BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-SOC2ConfidentialityControls - SPO Available' {
    BeforeAll {
        # Stub external cmdlets
        function Invoke-MgGraphRequest { param($Method, $Uri, $ErrorAction) }
        function Get-MgContext { }
        function Get-SPOTenant { }
        function Get-Command { param($Name, $ErrorAction) }
        function Get-DlpCompliancePolicy { }
        function Get-Label { }
        function Get-RetentionCompliancePolicy { }
        function Get-OrganizationConfig { }

        Mock Get-MgContext {
            return [PSCustomObject]@{ TenantId = 'test-tenant-id'; Account = 'admin@contoso.com' }
        }

        # SPO connected with restrictive sharing
        Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-SPOTenant' }
        Mock Get-SPOTenant {
            return [PSCustomObject]@{
                SharingCapability                      = 'ExistingExternalUserSharingOnly'
                DefaultSharingLinkType                 = 'Internal'
                RequireAnonymousLinksExpireInDays       = 30
                ShowPeoplePickerSuggestionsForGuestUsers = $false
            }
        }

        # DLP policies exist
        Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
        Mock Get-DlpCompliancePolicy {
            return @(
                [PSCustomObject]@{ Name = 'PII Protection'; Mode = 'Enable' }
            )
        }

        # Sensitivity labels exist
        Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-Label' }
        Mock Get-Label {
            return @(
                [PSCustomObject]@{ Name = 'Confidential'; ContentType = 'File, Email'; Disabled = $false }
            )
        }

        # Retention policies exist
        Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Get-RetentionCompliancePolicy' }
        Mock Get-RetentionCompliancePolicy {
            return @(
                [PSCustomObject]@{ Name = 'Default Retention'; Enabled = $true }
            )
        }

        # Graph mocks for guest access review
        Mock Invoke-MgGraphRequest {
            if ($Uri -match 'identityGovernance/accessReviews') {
                return @{ value = @(@{ displayName = 'Guest Review'; status = 'Completed' }) }
            }
            return @{ value = @() }
        }

        Mock Get-OrganizationConfig { return $null }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        $result = & "$PSScriptRoot/../../src/M365-Assess/SOC2/Get-SOC2ConfidentialityControls.ps1"
    }

    It 'should return control results' {
        $result | Should -Not -BeNullOrEmpty
    }

    It 'should have Confidentiality trust principle' {
        $result | ForEach-Object {
            $_.TrustPrinciple | Should -Be 'Confidentiality'
        }
    }

    It 'should include expected control properties' {
        $first = $result | Select-Object -First 1
        $first.PSObject.Properties.Name | Should -Contain 'TSCReference'
        $first.PSObject.Properties.Name | Should -Contain 'ControlId'
        $first.PSObject.Properties.Name | Should -Contain 'Status'
        $first.PSObject.Properties.Name | Should -Contain 'Severity'
    }

    It 'C-01 should pass when sharing is restricted' {
        $c01 = $result | Where-Object { $_.ControlId -eq 'C-01' }
        $c01.Status | Should -Be 'Pass'
    }

    It 'should have multiple controls assessed' {
        @($result).Count | Should -BeGreaterOrEqual 4
    }
}

Describe 'Get-SOC2ConfidentialityControls - SPO Not Available' {
    BeforeAll {
        function Invoke-MgGraphRequest { param($Method, $Uri, $ErrorAction) }
        function Get-MgContext { }
        function Get-SPOTenant { }
        function Get-Command { param($Name, $ErrorAction) }
        function Get-DlpCompliancePolicy { }
        function Get-Label { }
        function Get-RetentionCompliancePolicy { }
        function Get-OrganizationConfig { }

        Mock Get-MgContext {
            return [PSCustomObject]@{ TenantId = 'test-tenant-id' }
        }

        # SPO module not available
        Mock Get-Command { throw 'not found' } -ParameterFilter { $Name -eq 'Get-SPOTenant' }

        # Other Purview commands not available
        Mock Get-Command { throw 'not found' } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
        Mock Get-Command { throw 'not found' } -ParameterFilter { $Name -eq 'Get-Label' }
        Mock Get-Command { throw 'not found' } -ParameterFilter { $Name -eq 'Get-RetentionCompliancePolicy' }

        Mock Invoke-MgGraphRequest { return @{ value = @() } }
        Mock Get-OrganizationConfig { return $null }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        $result = & "$PSScriptRoot/../../src/M365-Assess/SOC2/Get-SOC2ConfidentialityControls.ps1"
    }

    It 'should still return controls (as Review status)' {
        $result | Should -Not -BeNullOrEmpty
    }

    It 'SPO-dependent controls should be Review' {
        $c01 = $result | Where-Object { $_.ControlId -eq 'C-01' }
        $c01.Status | Should -Be 'Review'
    }
}
