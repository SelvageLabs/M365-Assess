BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Compare-AssessmentBaseline' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/Compare-AssessmentBaseline.ps1"

        # Shared: current assessment folder
        $script:currentFolder = Join-Path -Path $TestDrive -ChildPath 'Current'
        $null = New-Item -Path $script:currentFolder -ItemType Directory -Force

        # Shared: baseline folder
        $script:baselineFolder = Join-Path -Path $TestDrive -ChildPath 'Baseline'
        $null = New-Item -Path $script:baselineFolder -ItemType Directory -Force

        # Write baseline metadata (required; excluded from JSON comparison by name filter)
        @{ label = 'Q1-2026'; tenant = 'test'; timestamp = '2026-01-01T00:00:00Z' } |
            ConvertTo-Json | Set-Content -Path (Join-Path -Path $script:baselineFolder -ChildPath 'manifest.json') -Encoding UTF8
    }

    Context 'when baseline folder does not exist' {
        It 'should return an empty array and emit an error' {
            $ErrorActionPreference = 'Continue'
            $result = Compare-AssessmentBaseline `
                -AssessmentFolder $script:currentFolder `
                -BaselineFolder (Join-Path -Path $TestDrive -ChildPath 'NonExistent') `
                2>$null
            @($result).Count | Should -Be 0
        }
    }

    Context 'when a check regressed (Pass -> Fail)' {
        BeforeAll {
            # Baseline JSON
            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA required'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $script:baselineFolder -ChildPath '10a-Entra-Security-Config.json') -Encoding UTF8

            # Current CSV
            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA required'; Status = 'Fail'; CurrentValue = 'Disabled'; Category = 'Identity' }
            ) | Export-Csv -Path (Join-Path -Path $script:currentFolder -ChildPath '10a-Entra-Security-Config.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should detect a Regressed change' {
            $result = @(Compare-AssessmentBaseline -AssessmentFolder $script:currentFolder -BaselineFolder $script:baselineFolder)
            $regressed = $result | Where-Object { $_.ChangeType -eq 'Regressed' -and $_.CheckId -eq 'ENTRA-MFA-001' }
            $regressed | Should -Not -BeNullOrEmpty
            $regressed.PreviousStatus | Should -Be 'Pass'
            $regressed.CurrentStatus  | Should -Be 'Fail'
        }
    }

    Context 'when a check improved (Fail -> Pass)' {
        BeforeAll {
            $baselineDir = Join-Path -Path $TestDrive -ChildPath 'BaselineImproved'
            $currentDir  = Join-Path -Path $TestDrive -ChildPath 'CurrentImproved'
            $null = New-Item -Path $baselineDir -ItemType Directory -Force
            $null = New-Item -Path $currentDir  -ItemType Directory -Force

            @{ label = 'test' } | ConvertTo-Json |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath 'manifest.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-CA-001'; Setting = 'CA policy'; Status = 'Fail'; CurrentValue = 'Disabled'; Category = 'Access' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath '11a-CA-Security-Config.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-CA-001'; Setting = 'CA policy'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Access' }
            ) | Export-Csv -Path (Join-Path -Path $currentDir -ChildPath '11a-CA-Security-Config.csv') -NoTypeInformation -Encoding UTF8

            $script:improvedResult = @(Compare-AssessmentBaseline -AssessmentFolder $currentDir -BaselineFolder $baselineDir)
        }

        It 'should detect an Improved change' {
            $improved = $script:improvedResult | Where-Object { $_.ChangeType -eq 'Improved' }
            $improved | Should -Not -BeNullOrEmpty
            $improved.PreviousStatus | Should -Be 'Fail'
            $improved.CurrentStatus  | Should -Be 'Pass'
        }
    }

    Context 'when a check is new (in current only)' {
        BeforeAll {
            $baselineDir = Join-Path -Path $TestDrive -ChildPath 'BaselineNew'
            $currentDir  = Join-Path -Path $TestDrive -ChildPath 'CurrentNew'
            $null = New-Item -Path $baselineDir -ItemType Directory -Force
            $null = New-Item -Path $currentDir  -ItemType Directory -Force

            @{ label = 'test' } | ConvertTo-Json |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath 'manifest.json') -Encoding UTF8

            # Baseline has no matching check
            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-OLD-001'; Setting = 'Old check'; Status = 'Pass'; CurrentValue = 'Yes'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath '10a-Entra-Security-Config.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-OLD-001'; Setting = 'Old check'; Status = 'Pass'; CurrentValue = 'Yes'; Category = 'Identity' }
                [PSCustomObject]@{ CheckId = 'ENTRA-NEW-001'; Setting = 'New check'; Status = 'Pass'; CurrentValue = 'Yes'; Category = 'Identity' }
            ) | Export-Csv -Path (Join-Path -Path $currentDir -ChildPath '10a-Entra-Security-Config.csv') -NoTypeInformation -Encoding UTF8

            $script:newResult = @(Compare-AssessmentBaseline -AssessmentFolder $currentDir -BaselineFolder $baselineDir)
        }

        It 'should detect a New check' {
            $new = $script:newResult | Where-Object { $_.ChangeType -eq 'New' -and $_.CheckId -eq 'ENTRA-NEW-001' }
            $new | Should -Not -BeNullOrEmpty
            $new.PreviousStatus | Should -Be ''
            $new.CurrentStatus  | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when a check is removed (in baseline only)' {
        BeforeAll {
            $baselineDir = Join-Path -Path $TestDrive -ChildPath 'BaselineRemoved'
            $currentDir  = Join-Path -Path $TestDrive -ChildPath 'CurrentRemoved'
            $null = New-Item -Path $baselineDir -ItemType Directory -Force
            $null = New-Item -Path $currentDir  -ItemType Directory -Force

            @{ label = 'test' } | ConvertTo-Json |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath 'manifest.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-GONE-001'; Setting = 'Removed check'; Status = 'Pass'; CurrentValue = 'Yes'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath '10a-Entra-Security-Config.json') -Encoding UTF8

            # Current CSV has no checks (empty-ish — just headers — but no rows that would match)
            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA'; Status = 'Pass'; CurrentValue = 'Yes'; Category = 'Identity' }
            ) | Export-Csv -Path (Join-Path -Path $currentDir -ChildPath '10a-Entra-Security-Config.csv') -NoTypeInformation -Encoding UTF8

            $script:removedResult = @(Compare-AssessmentBaseline -AssessmentFolder $currentDir -BaselineFolder $baselineDir)
        }

        It 'should detect a Removed check' {
            $removed = $script:removedResult | Where-Object { $_.ChangeType -eq 'Removed' -and $_.CheckId -eq 'ENTRA-GONE-001' }
            $removed | Should -Not -BeNullOrEmpty
            $removed.CurrentStatus | Should -Be ''
        }
    }

    Context 'when a check value changed but status is unchanged' {
        BeforeAll {
            $baselineDir = Join-Path -Path $TestDrive -ChildPath 'BaselineModified'
            $currentDir  = Join-Path -Path $TestDrive -ChildPath 'CurrentModified'
            $null = New-Item -Path $baselineDir -ItemType Directory -Force
            $null = New-Item -Path $currentDir  -ItemType Directory -Force

            @{ label = 'test' } | ConvertTo-Json |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath 'manifest.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'EXO-SPF-001'; Setting = 'SPF record'; Status = 'Pass'; CurrentValue = 'v=spf1 include:old.com ~all'; Category = 'Email' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath '15a-EXO-Security-Config.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'EXO-SPF-001'; Setting = 'SPF record'; Status = 'Pass'; CurrentValue = 'v=spf1 include:new.com ~all'; Category = 'Email' }
            ) | Export-Csv -Path (Join-Path -Path $currentDir -ChildPath '15a-EXO-Security-Config.csv') -NoTypeInformation -Encoding UTF8

            $script:modifiedResult = @(Compare-AssessmentBaseline -AssessmentFolder $currentDir -BaselineFolder $baselineDir)
        }

        It 'should detect a Modified change' {
            $modified = $script:modifiedResult | Where-Object { $_.ChangeType -eq 'Modified' -and $_.CheckId -eq 'EXO-SPF-001' }
            $modified | Should -Not -BeNullOrEmpty
            $modified.PreviousValue | Should -BeLike '*old.com*'
            $modified.CurrentValue  | Should -BeLike '*new.com*'
        }
    }

    Context 'when a check is unchanged' {
        BeforeAll {
            $baselineDir = Join-Path -Path $TestDrive -ChildPath 'BaselineUnchanged'
            $currentDir  = Join-Path -Path $TestDrive -ChildPath 'CurrentUnchanged'
            $null = New-Item -Path $baselineDir -ItemType Directory -Force
            $null = New-Item -Path $currentDir  -ItemType Directory -Force

            @{ label = 'test' } | ConvertTo-Json |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath 'manifest.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-PIM-001'; Setting = 'PIM'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath '10a-Entra-Security-Config.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-PIM-001'; Setting = 'PIM'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Identity' }
            ) | Export-Csv -Path (Join-Path -Path $currentDir -ChildPath '10a-Entra-Security-Config.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should return an empty result for identical checks' {
            $result = @(Compare-AssessmentBaseline -AssessmentFolder $currentDir -BaselineFolder $baselineDir)
            $result.Count | Should -Be 0
        }
    }

    Context 'when the section label is derived from the CSV filename' {
        BeforeAll {
            $baselineDir = Join-Path -Path $TestDrive -ChildPath 'BaselineSection'
            $currentDir  = Join-Path -Path $TestDrive -ChildPath 'CurrentSection'
            $null = New-Item -Path $baselineDir -ItemType Directory -Force
            $null = New-Item -Path $currentDir  -ItemType Directory -Force

            @{ label = 'test' } | ConvertTo-Json |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath 'manifest.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'EXO-DKIM-001'; Setting = 'DKIM'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Email' }
            ) | ConvertTo-Json -Depth 5 |
                Set-Content -Path (Join-Path -Path $baselineDir -ChildPath '15b-Exchange-Online-Security-Config.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'EXO-DKIM-001'; Setting = 'DKIM'; Status = 'Fail'; CurrentValue = 'Disabled'; Category = 'Email' }
            ) | Export-Csv -Path (Join-Path -Path $currentDir -ChildPath '15b-Exchange-Online-Security-Config.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should strip numeric prefix and Security-Config suffix from filename' {
            $result = @(Compare-AssessmentBaseline -AssessmentFolder $currentDir -BaselineFolder $baselineDir)
            $result[0].Section | Should -Be 'Exchange Online'
        }
    }
}
