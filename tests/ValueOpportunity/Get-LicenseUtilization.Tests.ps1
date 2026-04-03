BeforeAll {
    . "$PSScriptRoot/../../src/M365-Assess/ValueOpportunity/Get-LicenseUtilization.ps1"
    $featureMapPath = Join-Path $PSScriptRoot '../../src/M365-Assess/controls/sku-feature-map.json'
    $script:featureMap = Get-Content $featureMapPath -Raw | ConvertFrom-Json
}

Describe 'Get-LicenseUtilization' {
    It 'Should mark premium features as licensed when tenant has required service plan' {
        $mockLicenses = @{
            ActiveServicePlans = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('AAD_PREMIUM_P2', 'EXCHANGE_S_ENTERPRISE'),
                [System.StringComparer]::OrdinalIgnoreCase
            )
            SkuPartNumbers = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('ENTERPRISEPREMIUM'),
                [System.StringComparer]::OrdinalIgnoreCase
            )
        }

        $results = Get-LicenseUtilization -TenantLicenses $mockLicenses -FeatureMap $script:featureMap
        $pim = $results | Where-Object { $_.FeatureId -eq 'pim' }
        $pim.IsLicensed | Should -Be $true
    }

    It 'Should mark premium features as not licensed when plan is missing' {
        $mockLicenses = @{
            ActiveServicePlans = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('EXCHANGE_S_ENTERPRISE'),
                [System.StringComparer]::OrdinalIgnoreCase
            )
            SkuPartNumbers = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@('STANDARDPACK'),
                [System.StringComparer]::OrdinalIgnoreCase
            )
        }

        $results = Get-LicenseUtilization -TenantLicenses $mockLicenses -FeatureMap $script:featureMap
        $pim = $results | Where-Object { $_.FeatureId -eq 'pim' }
        $pim.IsLicensed | Should -Be $false
    }

    It 'Should mark STANDARD (E3 baseline) features as always licensed' {
        $mockLicenses = @{
            ActiveServicePlans = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            SkuPartNumbers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }

        $results = Get-LicenseUtilization -TenantLicenses $mockLicenses -FeatureMap $script:featureMap
        # Find a feature that uses STANDARD plan (E3 baseline)
        $baseline = $results | Where-Object { $_.SourcePlans -match 'E3 Baseline' } | Select-Object -First 1
        $baseline.IsLicensed | Should -Be $true
    }

    It 'Should return one row per feature' {
        $mockLicenses = @{
            ActiveServicePlans = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            SkuPartNumbers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }

        $results = Get-LicenseUtilization -TenantLicenses $mockLicenses -FeatureMap $script:featureMap
        $results.Count | Should -Be $script:featureMap.features.Count
    }
}
