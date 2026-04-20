BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Compare-M365Baseline' {
    BeforeAll {
        # Dot-source Build-DriftHtml first so Compare-M365Baseline's runtime check finds it
        . "$PSScriptRoot/../../src/M365-Assess/Common/Build-DriftHtml.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/Compare-M365Baseline.ps1"

        $script:outputFolder  = Join-Path -Path $TestDrive -ChildPath 'Output'
        $script:baselinesRoot = Join-Path -Path $script:outputFolder -ChildPath 'Baselines'
        $null = New-Item -Path $script:outputFolder -ItemType Directory -Force
    }

    Context 'when BaselineA folder does not exist' {
        It 'should emit an error and return no output' {
            $result = Compare-M365Baseline -BaselineA 'Ghost' -TenantId 'contoso.com' `
                -OutputFolder $script:outputFolder -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when explicit BaselineB folder does not exist' {
        BeforeAll {
            $tenantId = 'noB.test'
            $folderA = Join-Path $script:baselinesRoot -ChildPath "Q1_${tenantId}"
            $null = New-Item -Path $folderA -ItemType Directory -Force
            @{ SavedAt = '2026-01-01T00:00:00Z' } | ConvertTo-Json |
                Set-Content -Path (Join-Path $folderA 'manifest.json') -Encoding UTF8
        }

        It 'should emit an error and return no output' {
            $result = Compare-M365Baseline -BaselineA 'Q1' -BaselineB 'Ghost' `
                -TenantId 'noB.test' -OutputFolder $script:outputFolder -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when both baselines have identical data' {
        BeforeAll {
            $tenantId = 'identical.test'
            $folderA  = Join-Path $script:baselinesRoot -ChildPath "Q1_${tenantId}"
            $folderB  = Join-Path $script:baselinesRoot -ChildPath "Q2_${tenantId}"
            $null = New-Item -Path $folderA, $folderB -ItemType Directory -Force

            $checks = @(
                [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA Required'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5
            Set-Content -Path (Join-Path $folderA 'entra.json') -Value $checks -Encoding UTF8
            Set-Content -Path (Join-Path $folderB 'entra.json') -Value $checks -Encoding UTF8

            $script:outPathIdentical = Join-Path $TestDrive 'identical-drift.html'
            $script:resultIdentical  = Compare-M365Baseline -BaselineA 'Q1' -BaselineB 'Q2' `
                -TenantId $tenantId -OutputFolder $script:outputFolder -OutputPath $script:outPathIdentical
        }

        It 'should report 0 changes' {
            $script:resultIdentical | Should -Match '0 changes'
        }

        It 'should create the output HTML file' {
            Test-Path $script:outPathIdentical | Should -BeTrue
        }
    }

    Context 'when a check regressed (Pass -> Fail)' {
        BeforeAll {
            $tenantId = 'regressed.test'
            $folderA  = Join-Path $script:baselinesRoot -ChildPath "Q1_${tenantId}"
            $folderB  = Join-Path $script:baselinesRoot -ChildPath "Q2_${tenantId}"
            $null = New-Item -Path $folderA, $folderB -ItemType Directory -Force

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA Required'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folderA 'entra.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'ENTRA-MFA-001'; Setting = 'MFA Required'; Status = 'Fail'; CurrentValue = 'Disabled'; Category = 'Identity' }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folderB 'entra.json') -Encoding UTF8

            $script:outPathRegressed = Join-Path $TestDrive 'regressed-drift.html'
            $script:resultRegressed  = Compare-M365Baseline -BaselineA 'Q1' -BaselineB 'Q2' `
                -TenantId $tenantId -OutputFolder $script:outputFolder -OutputPath $script:outPathRegressed
        }

        It 'should report 1 change' {
            $script:resultRegressed | Should -Match '1 changes'
        }

        It 'should write an HTML file containing the Regressed classification' {
            $html = Get-Content $script:outPathRegressed -Raw
            $html | Should -Match 'Regressed'
        }

        It 'should include the check setting name in the HTML' {
            $html = Get-Content $script:outPathRegressed -Raw
            $html | Should -Match 'MFA Required'
        }
    }

    Context 'when a check improved (Fail -> Pass)' {
        BeforeAll {
            $tenantId = 'improved.test'
            $folderA  = Join-Path $script:baselinesRoot -ChildPath "Q1_${tenantId}"
            $folderB  = Join-Path $script:baselinesRoot -ChildPath "Q2_${tenantId}"
            $null = New-Item -Path $folderA, $folderB -ItemType Directory -Force

            @(
                [PSCustomObject]@{ CheckId = 'CA-001'; Setting = 'Block Legacy Auth'; Status = 'Fail'; CurrentValue = 'Off'; Category = 'CA' }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folderA 'ca.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'CA-001'; Setting = 'Block Legacy Auth'; Status = 'Pass'; CurrentValue = 'Enabled'; Category = 'CA' }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folderB 'ca.json') -Encoding UTF8

            $script:outPathImproved = Join-Path $TestDrive 'improved-drift.html'
            Compare-M365Baseline -BaselineA 'Q1' -BaselineB 'Q2' -TenantId $tenantId `
                -OutputFolder $script:outputFolder -OutputPath $script:outPathImproved | Out-Null
        }

        It 'should write an HTML file containing the Improved classification' {
            $html = Get-Content $script:outPathImproved -Raw
            $html | Should -Match 'Improved'
        }
    }

    Context 'when BaselineB is omitted and another baseline exists for the tenant' {
        BeforeAll {
            $tenantId = 'autodisc.test'
            $folderA  = Join-Path $script:baselinesRoot -ChildPath "Q1_${tenantId}"
            $folderB  = Join-Path $script:baselinesRoot -ChildPath "Q2_${tenantId}"
            $null = New-Item -Path $folderA, $folderB -ItemType Directory -Force

            @(
                [PSCustomObject]@{ CheckId = 'SPO-001'; Setting = 'External Sharing'; Status = 'Pass'; CurrentValue = 'Off'; Category = 'SharePoint' }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folderA 'spo.json') -Encoding UTF8

            @(
                [PSCustomObject]@{ CheckId = 'SPO-001'; Setting = 'External Sharing'; Status = 'Fail'; CurrentValue = 'On'; Category = 'SharePoint' }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folderB 'spo.json') -Encoding UTF8

            $script:outPathAuto = Join-Path $TestDrive 'autodisc-drift.html'
        }

        It 'should auto-discover the other baseline and generate a report without error' {
            { Compare-M365Baseline -BaselineA 'Q1' -TenantId $tenantId `
                -OutputFolder $script:outputFolder -OutputPath $script:outPathAuto } | Should -Not -Throw
        }

        It 'should create the output HTML file' {
            Test-Path $script:outPathAuto | Should -BeTrue
        }
    }

    Context 'when no other baseline exists for auto-discovery' {
        BeforeAll {
            $tenantId = 'lonely.test'
            $folderA  = Join-Path $script:baselinesRoot -ChildPath "Q1_${tenantId}"
            $null = New-Item -Path $folderA -ItemType Directory -Force
        }

        It 'should emit an error and return no output' {
            $result = Compare-M365Baseline -BaselineA 'Q1' -TenantId $tenantId `
                -OutputFolder $script:outputFolder -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}
