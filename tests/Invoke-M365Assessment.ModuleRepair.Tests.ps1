BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Module repair detection' {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../Invoke-M365Assessment.ps1"
        $src = Get-Content -Path $scriptPath -Raw
    }

    Context 'Repair action structure' {
        It 'Should define repairActions list' {
            $src | Should -Match 'repairActions'
        }

        It 'Should check Graph module conditionally on needsGraph' {
            $src | Should -Match 'needsGraph.*-and.*-not.*graphModule'
        }

        It 'Should check EXO module conditionally on needsExo' {
            $src | Should -Match 'needsExo.*-and.*-not.*exoModule'
        }

        It 'Should check PowerBI module conditionally on needsPowerBI' {
            $src | Should -Match 'needsPowerBI.*-and.*-not.*PowerBI'
        }

        It 'Should include RequiredVersion field in repair actions' {
            $src | Should -Match 'RequiredVersion'
        }

        It 'Should set EXO RequiredVersion to 3.7.1' {
            $src | Should -Match "RequiredVersion.*=.*'3\.7\.1'"
        }
    }

    Context 'NonInteractive parameter' {
        It 'Should have NonInteractive switch parameter' {
            $src | Should -Match '\[switch\]\$NonInteractive'
        }

        It 'Should derive isInteractive from NonInteractive' {
            $src | Should -Match 'isInteractive.*=.*-not \$NonInteractive'
        }
    }

    Context 'Tier structure' {
        It 'Should define Install tier' {
            $src | Should -Match "Tier\s*=\s*'Install'"
        }

        It 'Should define Downgrade tier' {
            $src | Should -Match "Tier\s*=\s*'Downgrade'"
        }

        It 'Should define FileCopy tier' {
            $src | Should -Match "Tier\s*=\s*'FileCopy'"
        }
    }

    Context 'No Invoke-Expression' {
        It 'Should never use Invoke-Expression for module installation' {
            $src | Should -Not -Match 'Invoke-Expression.*Install-Module'
            $src | Should -Not -Match 'Invoke-Expression.*\$action\.InstallCmd'
        }
    }
}
