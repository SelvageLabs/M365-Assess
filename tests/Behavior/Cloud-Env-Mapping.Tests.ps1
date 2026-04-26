Describe 'Cloud environment mapping (C5 #784)' {

    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot '../../src/M365-Assess/Common/Connect-Service.ps1'
        $script:content = Get-Content $script:scriptPath -Raw
    }

    Context 'Connect-Service supports the four documented clouds' {
        It 'should declare commercial / gcc / gcchigh / dod in the M365Environment ValidateSet' {
            $script:content | Should -Match "ValidateSet\(\s*'commercial'\s*,\s*'gcc'\s*,\s*'gcchigh'\s*,\s*'dod'\s*\)"
        }

        It 'should map gcchigh to the USGov Graph environment' {
            $script:content | Should -Match "GraphEnvironment\s*=\s*'USGov'"
        }

        It 'should map dod to the USGovDoD Graph environment' {
            $script:content | Should -Match "GraphEnvironment\s*=\s*'USGovDoD'"
        }

        It 'should route gcchigh EXO to O365USGovGCCHigh' {
            $script:content | Should -Match "ExoEnvironment\s*=\s*'O365USGovGCCHigh'"
        }

        It 'should route dod EXO to O365USGovDoD' {
            $script:content | Should -Match "ExoEnvironment\s*=\s*'O365USGovDoD'"
        }

        It 'should route gcchigh Purview to the .us compliance endpoint' {
            $script:content | Should -Match 'ps\.compliance\.protection\.office365\.us'
        }

        It 'should route dod Purview to the L5 compliance endpoint' {
            $script:content | Should -Match 'l5\.ps\.compliance\.protection\.office365\.us'
        }
    }

    Context 'Invoke-M365Assessment exposes the same environment values' {
        It 'should accept the same four env values on the entry point' {
            $invokePath = Join-Path $PSScriptRoot '../../src/M365-Assess/Invoke-M365Assessment.ps1'
            $invokeContent = Get-Content $invokePath -Raw
            $invokeContent | Should -Match "ValidateSet\(\s*'commercial'\s*,\s*'gcc'\s*,\s*'gcchigh'\s*,\s*'dod'\s*\)"
        }
    }
}
