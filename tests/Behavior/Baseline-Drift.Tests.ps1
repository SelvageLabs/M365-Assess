BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/M365-Assess/Orchestrator/Compare-AssessmentBaseline.ps1')
}

Describe 'Baseline drift comparison (C5 #784)' {

    Context 'when a check is renamed' {
        It 'should classify a renamed CheckId as Removed + New, not as Modified' {
            $tempBaseline = Join-Path $TestDrive 'baseline'
            $tempCurrent  = Join-Path $TestDrive 'current'
            $null = New-Item -ItemType Directory -Path $tempBaseline -Force
            $null = New-Item -ItemType Directory -Path $tempCurrent -Force

            # Baseline has X-001
            @(
                @{ CheckId = 'X-001'; Setting = 'a'; CurrentValue = 'old'; Status = 'Fail'; Category = 'Test' }
            ) | ConvertTo-Json | Set-Content (Join-Path $tempBaseline 'fixture-Security-Config.json')
            @{} | ConvertTo-Json | Set-Content (Join-Path $tempBaseline 'manifest.json')

            # Current has X-002 (renamed) -- Compare expects two CSV files for currents
            @(
                [PSCustomObject]@{ CheckId = 'X-002'; Setting = 'a'; CurrentValue = 'old'; Status = 'Fail'; Category = 'Test' }
            ) | Export-Csv -Path (Join-Path $tempCurrent 'fixture-Security-Config.csv') -NoTypeInformation

            $drift = Compare-AssessmentBaseline -AssessmentFolder $tempCurrent -BaselineFolder $tempBaseline

            $newRows     = @($drift | Where-Object ChangeType -eq 'New')
            $removedRows = @($drift | Where-Object ChangeType -eq 'Removed')
            $newRows.Count     | Should -Be 1
            $removedRows.Count | Should -Be 1
        }
    }

    Context 'when status changes from Pass to Fail' {
        It 'should classify the change as Regressed' {
            $tempBaseline = Join-Path $TestDrive 'baseline-2'
            $tempCurrent  = Join-Path $TestDrive 'current-2'
            $null = New-Item -ItemType Directory -Path $tempBaseline -Force
            $null = New-Item -ItemType Directory -Path $tempCurrent -Force

            @(
                @{ CheckId = 'X-001'; Setting = 'mfa'; CurrentValue = 'enabled'; Status = 'Pass'; Category = 'Identity' }
            ) | ConvertTo-Json | Set-Content (Join-Path $tempBaseline 'fixture-Security-Config.json')
            @{} | ConvertTo-Json | Set-Content (Join-Path $tempBaseline 'manifest.json')

            @(
                [PSCustomObject]@{ CheckId = 'X-001'; Setting = 'mfa'; CurrentValue = 'disabled'; Status = 'Fail'; Category = 'Identity' }
            ) | Export-Csv -Path (Join-Path $tempCurrent 'fixture-Security-Config.csv') -NoTypeInformation

            $drift = Compare-AssessmentBaseline -AssessmentFolder $tempCurrent -BaselineFolder $tempBaseline

            $regressed = @($drift | Where-Object ChangeType -eq 'Regressed')
            $regressed.Count | Should -Be 1
            $regressed[0].CheckId | Should -Be 'X-001'
        }
    }

    Context 'when status changes from Fail to Pass' {
        It 'should classify the change as Improved' {
            $tempBaseline = Join-Path $TestDrive 'baseline-3'
            $tempCurrent  = Join-Path $TestDrive 'current-3'
            $null = New-Item -ItemType Directory -Path $tempBaseline -Force
            $null = New-Item -ItemType Directory -Path $tempCurrent -Force

            @(
                @{ CheckId = 'X-001'; Setting = 'mfa'; CurrentValue = 'disabled'; Status = 'Fail'; Category = 'Identity' }
            ) | ConvertTo-Json | Set-Content (Join-Path $tempBaseline 'fixture-Security-Config.json')
            @{} | ConvertTo-Json | Set-Content (Join-Path $tempBaseline 'manifest.json')

            @(
                [PSCustomObject]@{ CheckId = 'X-001'; Setting = 'mfa'; CurrentValue = 'enabled'; Status = 'Pass'; Category = 'Identity' }
            ) | Export-Csv -Path (Join-Path $tempCurrent 'fixture-Security-Config.csv') -NoTypeInformation

            $drift = Compare-AssessmentBaseline -AssessmentFolder $tempCurrent -BaselineFolder $tempBaseline

            $improved = @($drift | Where-Object ChangeType -eq 'Improved')
            $improved.Count | Should -Be 1
        }
    }
}
