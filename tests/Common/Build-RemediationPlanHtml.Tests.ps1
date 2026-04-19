BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Build-RemediationPlanHtml' {
    BeforeAll {
        # ReportHelpers provides ConvertTo-HtmlSafe used inside the function
        . "$PSScriptRoot/../../src/M365-Assess/Common/ReportHelpers.ps1"

        # Build-RemediationPlanHtml is now a standalone file (extracted from Build-SectionHtml.ps1 in v2.0.0)
        . "$PSScriptRoot/../../src/M365-Assess/Common/Build-RemediationPlanHtml.ps1"
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }

    Context 'when there are no Fail or Warning findings' {
        It 'should return the empty-state placeholder' {
            $result = Build-RemediationPlanHtml -Findings @() -IsQuickScan $false
            $result | Should -Match 'No actionable findings'
        }

        It 'should return the empty-state placeholder when all findings are Pass' {
            $passFindings = @(
                [PSCustomObject]@{ CheckId = 'ID-001'; Setting = 'MFA'; Status = 'Pass'; RiskSeverity = 'High'; Section = 'Identity'; CurrentValue = 'Enabled'; Remediation = 'N/A' }
            )
            $result = Build-RemediationPlanHtml -Findings $passFindings -IsQuickScan $false
            $result | Should -Match 'No actionable findings'
        }
    }

    Context 'when findings include Fail and Warning rows' {
        BeforeAll {
            $script:testFindings = @(
                [PSCustomObject]@{ CheckId = 'DEF-001'; Setting = 'AntiPhish'; Status = 'Warning'; RiskSeverity = 'Medium'; Section = 'Security'; CurrentValue = 'Default'; Remediation = 'Enable strict preset policy' }
                [PSCustomObject]@{ CheckId = 'ID-002';  Setting = 'MFA';       Status = 'Fail';    RiskSeverity = 'Critical'; Section = 'Identity'; CurrentValue = 'Disabled'; Remediation = 'Set-MsolUser -UserPrincipalName user@domain.com -StrongAuthenticationRequirements ...' }
                [PSCustomObject]@{ CheckId = 'EXO-001'; Setting = 'DMARC';     Status = 'Pass';    RiskSeverity = 'High';    Section = 'Email';    CurrentValue = 'Pass';     Remediation = '' }
                [PSCustomObject]@{ CheckId = 'ID-003';  Setting = 'AdminMFA';  Status = 'Fail';    RiskSeverity = 'High';    Section = 'Identity'; CurrentValue = '3 admins no MFA'; Remediation = 'Enforce MFA for all admin roles' }
            )
        }

        It 'should exclude Pass-status findings from the output' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Not -Match 'DMARC'
        }

        It 'should include Fail findings in the output' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'MFA'
        }

        It 'should sort Critical findings before High findings in row order' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            # Critical row class must appear before the first High row class in the HTML
            $critPos = $result.IndexOf("remediation-row-critical")
            $highPos = $result.IndexOf("remediation-row-high")
            $critPos | Should -BeLessThan $highPos
        }

        It 'should render the full remediation text without truncation' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            # The long remediation string must appear in full, not truncated to 200 chars
            $result | Should -Match 'StrongAuthenticationRequirements'
        }

        It 'should include a copy button on every actionable row' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            # 3 actionable findings (2 Fail + 1 Warning) -> 3 copy buttons
            $copyButtonCount = ([regex]::Matches($result, 'copyRemediation\(this\)')).Count
            $copyButtonCount | Should -Be 3
        }

        It 'should display correct Critical count in stats row' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'remediation-stat-critical'
            $result | Should -Match '<span class=.stat-num.>1</span>'
        }

        It 'should display correct High count in stats row' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'remediation-stat-high'
            $result | Should -Match '<span class=.stat-num.>1</span>'
        }

        It 'should render severity chip buttons instead of a select dropdown' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'remSeverityChips'
            $result | Should -Not -Match 'remSeverityFilter'
        }

        It 'should render section chip buttons when multiple sections are present' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'remSectionChips'
            $result | Should -Not -Match 'remSectionFilter'
        }

        It 'should add data-severity attribute to each row for JS filtering' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match "data-severity='Critical'"
            $result | Should -Match "data-severity='High'"
        }

        It 'should wrap everything in a collapsible section details element' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match "details class='section'"
            $result | Should -Match 'Remediation Action Plan'
        }

        It 'should include a collector-detail wrapper for the table' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match "details class='collector-detail'"
        }

        It 'should use table-wrapper for the compact findings table' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'remediation-table-wrapper'
            $result | Should -Not -Match 'rem-table-viewport'
            $result | Should -Not -Match 'rem-show-more'
        }

        It 'should render a column picker bar with all expected columns' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match 'col-picker-bar'
            $result | Should -Match "data-col-key='Severity'"
            $result | Should -Match "data-col-key='CheckId'"
        }

        It 'should render Check ID column hidden by default' {
            $result = Build-RemediationPlanHtml -Findings $script:testFindings -IsQuickScan $false
            $result | Should -Match "data-col-default='hidden'"
        }
    }

    Context 'when IsQuickScan is true or false' {
        It 'should not include a QuickScan note in the output (note was removed as unhelpful)' {
            $finding = @(
                [PSCustomObject]@{ CheckId = 'ID-001'; Setting = 'MFA'; Status = 'Fail'; RiskSeverity = 'Critical'; Section = 'Identity'; CurrentValue = 'Off'; Remediation = 'Enable MFA' }
            )
            $resultTrue  = Build-RemediationPlanHtml -Findings $finding -IsQuickScan $true
            $resultFalse = Build-RemediationPlanHtml -Findings $finding -IsQuickScan $false
            $resultTrue  | Should -Not -Match 'Quick Scan mode'
            $resultFalse | Should -Not -Match 'Quick Scan mode'
        }
    }

    Context 'when only one section is present' {
        It 'should still render section chips (single section is still informative)' {
            $findings = @(
                [PSCustomObject]@{ CheckId = 'ID-001'; Setting = 'MFA';      Status = 'Fail'; RiskSeverity = 'Critical'; Section = 'Identity'; CurrentValue = 'Off'; Remediation = 'Enable MFA' }
                [PSCustomObject]@{ CheckId = 'ID-002'; Setting = 'AdminMFA'; Status = 'Fail'; RiskSeverity = 'High';     Section = 'Identity'; CurrentValue = 'Off'; Remediation = 'Enforce admin MFA' }
            )
            $result = Build-RemediationPlanHtml -Findings $findings -IsQuickScan $false
            $result | Should -Match 'remSectionChips'
            $result | Should -Not -Match 'remSectionFilter'
        }
    }
}
