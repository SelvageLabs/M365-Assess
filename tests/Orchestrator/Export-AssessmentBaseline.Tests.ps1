BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Export-AssessmentBaseline' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/Export-AssessmentBaseline.ps1"

        # Create a temp assessment folder with test CSVs
        $script:tempAssessment = Join-Path -Path $TestDrive -ChildPath 'Assessment_20260101_000000'
        $null = New-Item -Path $script:tempAssessment -ItemType Directory -Force

        # Security-config CSV (has CheckId + Status) — should be baselined
        $securityCsvPath = Join-Path -Path $script:tempAssessment -ChildPath '10a-Entra-Security-Config.csv'
        @(
            [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA required'; Status = 'Pass'; CurrentValue = 'Enabled' }
            [PSCustomObject]@{ CheckId = 'ENTRA-MFA-002'; Setting = 'MFA legacy'; Status = 'Fail'; CurrentValue = 'Disabled' }
        ) | Export-Csv -Path $securityCsvPath -NoTypeInformation -Encoding UTF8

        # Non-security-config CSV (no CheckId column) — should be skipped
        $nonSecCsvPath = Join-Path -Path $script:tempAssessment -ChildPath '02-User-Summary.csv'
        @(
            [PSCustomObject]@{ DisplayName = 'User One'; UPN = 'user@test.com' }
        ) | Export-Csv -Path $nonSecCsvPath -NoTypeInformation -Encoding UTF8

        $script:tempOutput = Join-Path -Path $TestDrive -ChildPath 'Output'
        $null = New-Item -Path $script:tempOutput -ItemType Directory -Force
    }

    Context 'when exporting a valid assessment folder' {
        BeforeAll {
            $script:result = Export-AssessmentBaseline `
                -AssessmentFolder $script:tempAssessment `
                -OutputFolder $script:tempOutput `
                -Label 'Q1-2026' `
                -TenantId 'contoso.com' `
                -Sections @('Entra', 'Exchange') `
                -Version '1.11.0'
        }

        It 'should return the baseline folder path' {
            $script:result | Should -Not -BeNullOrEmpty
            $script:result | Should -Match 'Baselines'
        }

        It 'should create the baseline directory' {
            Test-Path -Path $script:result -PathType Container | Should -Be $true
        }

        It 'should write a manifest file' {
            $metaPath = Join-Path -Path $script:result -ChildPath 'manifest.json'
            Test-Path -Path $metaPath | Should -Be $true
        }

        It 'should write correct manifest fields' {
            $metaPath = Join-Path -Path $script:result -ChildPath 'manifest.json'
            $meta = Get-Content -Path $metaPath -Raw | ConvertFrom-Json
            $meta.Label             | Should -Be 'Q1-2026'
            $meta.TenantId          | Should -Be 'contoso.com'
            $meta.AssessmentVersion | Should -Be '1.11.0'
            $meta.Sections          | Should -Contain 'Entra'
            $meta.SavedAt           | Should -Not -BeNullOrEmpty
            $meta.CheckCount        | Should -BeGreaterOrEqual 0
        }

        It 'should serialize the security-config CSV to JSON' {
            $jsonPath = Join-Path -Path $script:result -ChildPath '10a-Entra-Security-Config.json'
            Test-Path -Path $jsonPath | Should -Be $true
            $rows = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            $rows.Count | Should -Be 2
            $rows[0].CheckId | Should -Be 'ENTRA-MFA-001'
        }

        It 'should skip the non-security-config CSV' {
            $skippedPath = Join-Path -Path $script:result -ChildPath '02-User-Summary.json'
            Test-Path -Path $skippedPath | Should -Be $false
        }

        It 'should label the baseline folder with sanitised label and tenant' {
            $script:result | Should -Match 'Q1-2026_contoso\.com'
        }
    }

    Context 'when the label contains special characters' {
        It 'should sanitise them for the folder name' {
            $dir = Export-AssessmentBaseline `
                -AssessmentFolder $script:tempAssessment `
                -OutputFolder $script:tempOutput `
                -Label 'Baseline 2026/Q1' `
                -TenantId 'contoso.com'
            $dir | Should -Match 'Baseline_2026_Q1_contoso\.com'
        }
    }
}
