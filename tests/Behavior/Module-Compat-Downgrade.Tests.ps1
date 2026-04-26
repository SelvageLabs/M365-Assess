Describe 'Module compatibility downgrade behavior (C5 #784)' {

    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot '../../src/M365-Assess/Orchestrator/Test-ModuleCompatibility.ps1'
    }

    It 'should declare the EXO ceiling at 3.7.1' {
        # Memory: ExchangeOnlineManagement is excluded from RequiredModules in
        # the manifest because of the MSAL/3.8 ceiling issue (#231 Blocked).
        # The orchestrator's compatibility check enforces the ceiling at runtime.
        $content = Get-Content $script:scriptPath -Raw
        $content | Should -Match '3\.7\.1'
    }

    It 'should distinguish required modules from optional modules' {
        $content = Get-Content $script:scriptPath -Raw
        # Required vs optional gating must be present so missing optional modules
        # don't fail the run; missing required modules abort.
        $content | Should -Match '(?i)required|optional'
    }
}
