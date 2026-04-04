BeforeAll {
    $mapPath = Join-Path $PSScriptRoot '../../src/M365-Assess/controls/sku-feature-map.json'
    $map = Get-Content $mapPath -Raw | ConvertFrom-Json
}

Describe 'SKU Feature Map Schema' {
    It 'Should have a version field' {
        $map.version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'Should have at least 6 categories' {
        $map.categories.Count | Should -BeGreaterOrEqual 6
    }

    It 'Should have at least 30 features' {
        $map.features.Count | Should -BeGreaterOrEqual 30
    }

    It 'Should have no duplicate featureIds' {
        $ids = $map.features | ForEach-Object { $_.featureId }
        $ids.Count | Should -Be ($ids | Sort-Object -Unique).Count
    }

    It 'Should have valid effortTier values' {
        $validTiers = @('Quick Win', 'Medium', 'Strategic')
        foreach ($f in $map.features) {
            $f.effortTier | Should -BeIn $validTiers -Because "$($f.featureId) has invalid effortTier"
        }
    }

    It 'Should reference valid category ids' {
        $catIds = $map.categories | ForEach-Object { $_.id }
        foreach ($f in $map.features) {
            $f.category | Should -BeIn $catIds -Because "$($f.featureId) references unknown category"
        }
    }

    It 'Should have requiredServicePlans as array on every feature' {
        foreach ($f in $map.features) {
            $f.requiredServicePlans | Should -Not -BeNullOrEmpty -Because "$($f.featureId) needs requiredServicePlans"
        }
    }

    It 'Should have checkIds as array on every feature' {
        foreach ($f in $map.features) {
            $f.PSObject.Properties.Name | Should -Contain 'checkIds' -Because "$($f.featureId) needs checkIds"
        }
    }

    It 'Should have learnUrl on every feature' {
        foreach ($f in $map.features) {
            $f.learnUrl | Should -Match '^https://' -Because "$($f.featureId) needs a Learn URL"
        }
    }

    It 'Should not use STANDARD sentinel in requiredServicePlans' {
        foreach ($f in $map.features) {
            $f.requiredServicePlans | Should -Not -Contain 'STANDARD' -Because "$($f.featureId) should use a real service plan ID, not the STANDARD sentinel"
        }
    }

    It 'Should reference CheckIds that exist in registry.json' {
        $registryPath = Join-Path $PSScriptRoot '../../src/M365-Assess/controls/registry.json'
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $registryIds = @($registry.checks | ForEach-Object { $_.checkId })
        foreach ($f in $map.features) {
            foreach ($checkId in $f.checkIds) {
                $registryIds | Should -Contain $checkId -Because "$($f.featureId) references CheckId '$checkId' which must exist in registry.json"
            }
        }
    }
}
