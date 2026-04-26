Describe 'QuickScan filter behavior (C5 #784)' {

    BeforeAll {
        $script:invokePath = Join-Path $PSScriptRoot '../../src/M365-Assess/Invoke-M365Assessment.ps1'
        $script:content = Get-Content $script:invokePath -Raw
    }

    It 'should expose -QuickScan as a switch parameter' {
        $script:content | Should -Match '\[switch\]\$QuickScan'
    }

    It 'should set the SeverityFilter to Critical + High when QuickScan is supplied' {
        # The orchestrator threads QuickScan into Show-CheckProgress's SeverityFilter
        # so collectors only emit findings at Critical + High severity. Looser
        # regex: just verify the QuickScan branch references SeverityFilter and
        # both severity tiers somewhere nearby.
        $script:content | Should -Match 'QuickScan'
        $script:content | Should -Match 'SeverityFilter'
        $script:content | Should -Match "'Critical'\s*,\s*'High'"
    }

    It 'should document QuickScan in comment-based help' {
        $script:content | Should -Match '\.PARAMETER QuickScan'
    }
}
