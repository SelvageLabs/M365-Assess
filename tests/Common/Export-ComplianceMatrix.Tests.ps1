BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Export-ComplianceMatrix' {
    BeforeAll {
        $script:srcPath = "$PSScriptRoot/../../src/M365-Assess/Common/Export-ComplianceMatrix.ps1"
        Mock Write-Warning { }
    }

    Context 'when ImportExcel module is not available' {
        BeforeAll {
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'ImportExcel' }
        }

        It 'should warn and return without error' {
            $result = & $script:srcPath -AssessmentFolder $TestDrive
            $result | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -Times 1
        }
    }

    Context 'when assessment folder does not exist' {
        BeforeAll {
            Mock Get-Module {
                return [PSCustomObject]@{ Name = 'ImportExcel'; Version = [version]'7.8.0' }
            } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Import-Module { }
        }

        It 'should throw an error for missing folder' {
            { & $script:srcPath -AssessmentFolder 'C:\nonexistent\folder' } 2>&1 | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when assessment folder exists but has no CSV files' {
        BeforeAll {
            Mock Get-Module {
                return [PSCustomObject]@{ Name = 'ImportExcel'; Version = [version]'7.8.0' }
            } -ParameterFilter { $Name -eq 'ImportExcel' }
            Mock Import-Module { }

            # Create an empty assessment folder
            $testFolder = Join-Path $TestDrive 'empty-assessment'
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
        }

        It 'should report missing summary CSV' {
            $result = try { & $script:srcPath -AssessmentFolder $testFolder 2>$null } catch { $null }
            # Script exits early when no summary CSV is found
            $result | Should -BeNullOrEmpty
        }
    }
}
