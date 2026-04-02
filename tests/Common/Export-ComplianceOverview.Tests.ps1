BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Export-ComplianceOverview' {
    BeforeAll {
        # Stub helper functions that Export-ComplianceOverview expects to be in scope
        function ConvertTo-HtmlSafe { param([string]$Text) return $Text }
        function Get-SvgHorizontalBar { return '<svg></svg>' }

        . "$PSScriptRoot/../../src/M365-Assess/Common/Export-ComplianceOverview.ps1"
    }

    Context 'when findings and frameworks are provided' {
        BeforeAll {
            $findings = @(
                [PSCustomObject]@{
                    CheckId      = 'ENTRA-ADMIN-001'
                    Setting      = 'Global Admin Count'
                    Status       = 'Pass'
                    RiskSeverity = 'High'
                    Section      = 'Identity'
                    Frameworks   = @{ 'cis-m365-v6' = @{ controlId = '1.1.3' } }
                }
                [PSCustomObject]@{
                    CheckId      = 'ENTRA-ADMIN-002'
                    Setting      = 'Admin Center Restricted'
                    Status       = 'Fail'
                    RiskSeverity = 'High'
                    Section      = 'Identity'
                    Frameworks   = @{ 'cis-m365-v6' = @{ controlId = '5.1.2.4' } }
                }
            )
            $controlRegistry = @{
                'ENTRA-ADMIN-001' = @{ checkId = 'ENTRA-ADMIN-001'; name = 'Global Admin Count'; hasAutomatedCheck = $true; frameworks = @{ 'cis-m365-v6' = @{ controlId = '1.1.3' } } }
                'ENTRA-ADMIN-002' = @{ checkId = 'ENTRA-ADMIN-002'; name = 'Admin Center'; hasAutomatedCheck = $true; frameworks = @{ 'cis-m365-v6' = @{ controlId = '5.1.2.4' } } }
            }
            $frameworks = @(
                @{
                    frameworkId    = 'cis-m365-v6'
                    name           = 'CIS Microsoft 365 Foundations Benchmark'
                    label          = 'CIS M365 v6.0.1'
                    filterFamily   = 'CIS'
                    scoringMethod  = 'profile-compliance'
                    totalControls  = 140
                    description    = 'CIS Benchmark for M365'
                    profiles       = @(@{ name = 'E3-L1'; label = 'E3 Level 1' })
                    controls       = @(
                        @{ controlId = '1.1.3'; title = 'GA Count'; profiles = @('E3-L1') }
                        @{ controlId = '5.1.2.4'; title = 'Admin Center'; profiles = @('E3-L1') }
                    )
                }
            )

            $result = Export-ComplianceOverview -Findings $findings -ControlRegistry $controlRegistry -Frameworks $frameworks -Sections @('Identity')
        }

        It 'should return HTML content' {
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should contain Compliance Overview heading' {
            $result | Should -Match 'Compliance Overview'
        }

        It 'should include framework label' {
            $result | Should -Match 'CIS'
        }
    }

    Context 'when FrameworkFilter limits output' {
        BeforeAll {
            $findings = @(
                [PSCustomObject]@{ CheckId = 'X-001'; Setting = 'Test'; Status = 'Pass'; RiskSeverity = 'Low'; Section = 'Identity'; Frameworks = @{} }
            )
            $controlRegistry = @{ 'X-001' = @{ checkId = 'X-001'; hasAutomatedCheck = $true; frameworks = @{} } }
            $frameworks = @(
                @{ frameworkId = 'cis-m365-v6'; name = 'CIS'; label = 'CIS'; filterFamily = 'CIS'; scoringMethod = 'pass-rate'; controls = @(); totalControls = 0 }
                @{ frameworkId = 'nist-csf'; name = 'NIST CSF'; label = 'NIST CSF'; filterFamily = 'NIST'; scoringMethod = 'pass-rate'; controls = @(); totalControls = 0 }
            )

            $result = Export-ComplianceOverview -Findings $findings -ControlRegistry $controlRegistry -Frameworks $frameworks -FrameworkFilter @('CIS') -Sections @('Identity')
        }

        It 'should include the filtered framework' {
            $result | Should -Match 'CIS'
        }
    }

    Context 'when no frameworks match filter' {
        BeforeAll {
            $findings = @(
                [PSCustomObject]@{ CheckId = 'X-001'; Setting = 'Test'; Status = 'Pass'; RiskSeverity = 'Low'; Section = 'Identity'; Frameworks = @{} }
            )
            $controlRegistry = @{ 'X-001' = @{ checkId = 'X-001'; hasAutomatedCheck = $true; frameworks = @{} } }
            $frameworks = @(
                @{ id = 'cis-m365-v6'; name = 'CIS'; filterFamily = 'CIS'; controls = @() }
            )

            $result = Export-ComplianceOverview -Findings $findings -ControlRegistry $controlRegistry -Frameworks $frameworks -FrameworkFilter @('HIPAA')
        }

        It 'should return empty string' {
            $result | Should -Be ''
        }
    }
}
