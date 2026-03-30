Describe 'Import-ControlRegistry' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Common/Import-ControlRegistry.ps1"
        $testRoot = "$PSScriptRoot/../../src/M365-Assess/controls"
    }

    It 'Returns a hashtable keyed by CheckId' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $registry | Should -BeOfType [hashtable]
        $registry.Keys | Should -Contain 'ENTRA-ADMIN-001'
    }

    It 'Each entry contains frameworks object' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $entry = $registry['ENTRA-ADMIN-001']
        $entry.frameworks | Should -Not -BeNullOrEmpty
        $entry.frameworks.'cis-m365-v6'.controlId | Should -Not -BeNullOrEmpty
    }

    It 'Builds a reverse lookup from CIS control ID to CheckId' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $reverseLookup = $registry['__cisReverseLookup']
        $reverseLookup['1.1.3'] | Should -Not -BeNullOrEmpty
        $reverseLookup['1.1.3'] | Should -Match '^[A-Z]+-[A-Z]+-\d{3}$'
    }

    It 'Returns empty hashtable when registry not found' {
        $result = Import-ControlRegistry -ControlsPath (Join-Path $TestDrive 'nonexistent') -WarningAction SilentlyContinue
        $result.Count | Should -Be 0
    }

    It 'Applies risk severity overlay from risk-severity.json' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        # At least one check should have a non-default severity
        $severities = @($registry.Keys | Where-Object { $_ -ne '__cisReverseLookup' } |
            ForEach-Object { $registry[$_].riskSeverity } | Sort-Object -Unique)
        $severities.Count | Should -BeGreaterThan 1 -Because 'risk-severity.json should override some defaults'
    }

    It 'Accepts CisFrameworkId parameter for reverse lookup' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot -CisFrameworkId 'cis-m365-v6'
        $reverseLookup = $registry['__cisReverseLookup']
        $reverseLookup.Count | Should -BeGreaterThan 0
    }

    It 'Falls back to local JSON when CheckID module is not available' {
        # This test verifies the fallback path works (CheckID module unlikely
        # to be installed in CI). The function should load from controls/registry.json.
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $registry.Keys.Count | Should -BeGreaterThan 10 -Because 'local registry.json should load as fallback'
    }
}
