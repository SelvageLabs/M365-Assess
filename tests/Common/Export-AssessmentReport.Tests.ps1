Describe 'Export-AssessmentReport HTML structure' {
    BeforeAll {
        # Read the raw script source to verify embedded HTML/CSS/JS patterns.
        # Full execution requires a live assessment folder with CSV data, so we
        # verify the template strings are present in the script source instead.
        $scriptPath = "$PSScriptRoot/../../Common/Export-AssessmentReport.ps1"
        $html = Get-Content -Path $scriptPath -Raw
    }

    Context 'Dual-metric framework cards' {
        It 'Should include coverage bar CSS classes in stylesheet' {
            $html | Should -Match 'coverage-bar'
            $html | Should -Match 'coverage-fill'
            $html | Should -Match 'coverage-label'
        }

        It 'Should include data-catalog-total attribute on framework cards' {
            $html | Should -Match 'data-catalog-total'
        }

        It 'Should include stat-sublabel in card HTML generation' {
            $html | Should -Match 'stat-sublabel'
        }
    }

    Context 'Expand/Collapse All buttons' {
        It 'Should include expand/collapse buttons in section panels' {
            $html | Should -Match 'expand-all-btn'
            $html | Should -Match 'collapse-all-btn'
            $html | Should -Match 'collector-detail'
        }

        It 'Should render expand/collapse buttons only for sections with multiple collectors' {
            $html | Should -Match "sectionCollectors\.Count -gt 1"
        }

        It 'Should include matrix-controls CSS class' {
            $html | Should -Match 'matrix-controls'
        }

        It 'Should hide matrix-controls in print media' {
            # Verify the print media block suppresses the buttons
            $html | Should -Match '\.matrix-controls \{ display: none; \}'
        }

        It 'Should wire expand button to open collector-detail panels in parent section' {
            $html | Should -Match "expand-all-btn"
            $html | Should -Match "d\.open = true"
        }

        It 'Should wire collapse button to close collector-detail panels in parent section' {
            $html | Should -Match "collapse-all-btn"
            $html | Should -Match "d\.open = false"
        }

        It 'Should use btn.closest to scope to parent section' {
            $html | Should -Match "btn\.closest\('\.section'\)"
        }
    }

    Context 'Section filter data preparation' {
        It 'Should include Section property in allCisFindings population' {
            $html | Should -Match "Section\s*=\s*\`$c\.Section"
        }

        It 'Should include data-section attribute on compliance table rows' {
            $html | Should -Match "data-section="
        }

        It 'Should embed complianceData JSON blob' {
            $html | Should -Match 'var complianceData\s*='
        }
    }
}
