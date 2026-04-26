BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/M365-Assess/Common/Get-BaselineTrend.ps1')

    function New-FakeBaseline {
        param(
            [string]$Root,
            [string]$Label,
            [string]$Suffix,
            [DateTime]$SavedAt,
            [hashtable]$StatusCounts = @{ Pass = 1; Fail = 0; Warning = 0 }
        )
        $folder = Join-Path $Root "${Label}_${Suffix}"
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $manifest = @{ Label = $Label; SavedAt = $SavedAt.ToUniversalTime().ToString('o'); Version = '2.9.0' }
        $manifest | ConvertTo-Json | Set-Content -Path (Join-Path $folder 'manifest.json') -Encoding UTF8
        # One synthetic security-config JSON with the documented shape.
        $rows = foreach ($s in $StatusCounts.Keys) {
            1..$StatusCounts[$s] | ForEach-Object { @{ CheckId = "X-$s-$_"; Status = $s } }
        }
        @($rows) | ConvertTo-Json | Set-Content -Path (Join-Path $folder 'sample-config.json') -Encoding UTF8
    }
}

Describe 'Get-BaselineTrend (regression: TypeName parser binding)' {

    BeforeEach {
        # TestDrive is shared per-Describe; clean to keep tests independent.
        $script:root = Join-Path $TestDrive 'Baselines'
        if (Test-Path $script:root) { Remove-Item -Path $script:root -Recurse -Force }
        New-Item -Path $script:root -ItemType Directory -Force | Out-Null
    }

    It 'does not throw the Object[] -> System.String TypeName binding error (v2.9.0 hotfix)' {
        # Regression: in v2.9.0 the implementation used
        #   New-Object -TypeName System.Collections.Generic.Dictionary[string, ...]
        # which the PS parser can interpret as an array literal -- producing
        # 'Cannot convert Object[] to System.String required by parameter TypeName'
        # at runtime, only when called from the report path, not from tests
        # that mocked around the line.
        New-FakeBaseline -Root $script:root -Label 'auto_2026-04-26' `
            -Suffix 'contoso.onmicrosoft.com' -SavedAt (Get-Date)
        { Get-BaselineTrend -BaselinesRoot $script:root -TenantId 'contoso.onmicrosoft.com' } |
            Should -Not -Throw
    }

    It 'returns one snapshot when one baseline matches the legacy TenantId suffix' {
        New-FakeBaseline -Root $script:root -Label 'auto_2026-04-26' `
            -Suffix 'contoso.onmicrosoft.com' -SavedAt (Get-Date)
        $result = @(Get-BaselineTrend -BaselinesRoot $script:root -TenantId 'contoso.onmicrosoft.com')
        $result.Count | Should -Be 1
    }

    It 'unions GUID-suffixed AND legacy TenantId-suffixed baselines (C1 #780)' {
        # Legacy folder
        New-FakeBaseline -Root $script:root -Label 'auto_2026-04-20' `
            -Suffix 'contoso.onmicrosoft.com' -SavedAt (Get-Date).AddDays(-6)
        # GUID-keyed folder
        $guid = '11111111-2222-3333-4444-555555555555'
        New-FakeBaseline -Root $script:root -Label 'auto_2026-04-26' `
            -Suffix $guid -SavedAt (Get-Date)
        $result = @(Get-BaselineTrend -BaselinesRoot $script:root `
            -TenantId 'contoso.onmicrosoft.com' -TenantGuid $guid)
        $result.Count | Should -Be 2
    }

    It 'returns an empty array when the baselines root does not exist' {
        $result = @(Get-BaselineTrend -BaselinesRoot (Join-Path $TestDrive 'nope') -TenantId 'x.onmicrosoft.com')
        $result.Count | Should -Be 0
    }
}
