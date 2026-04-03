BeforeAll {
    . "$PSScriptRoot/../../src/M365-Assess/ValueOpportunity/Get-FeatureReadiness.ps1"
}

Describe 'Get-FeatureReadiness' {
    BeforeAll {
        $script:mockFeatureMap = @{
            features = @(
                @{
                    featureId = 'feature-a'
                    name = 'Feature A'
                    category = 'identity-access'
                    effortTier = 'Quick Win'
                    requiredServicePlans = @('PLAN_A')
                    prerequisites = @()
                    learnUrl = 'https://learn.microsoft.com/test-a'
                }
                @{
                    featureId = 'feature-b'
                    name = 'Feature B'
                    category = 'identity-access'
                    effortTier = 'Medium'
                    requiredServicePlans = @('PLAN_B')
                    prerequisites = @('feature-a')
                    learnUrl = 'https://learn.microsoft.com/test-b'
                }
            )
            categories = @(@{ id = 'identity-access'; name = 'Identity & Access' })
        }
    }

    It 'Should mark Ready when licensed and no blockers' {
        $license = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; IsLicensed = $true }
            [PSCustomObject]@{ FeatureId = 'feature-b'; IsLicensed = $true }
        )
        $adoption = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; AdoptionState = 'Adopted' }
            [PSCustomObject]@{ FeatureId = 'feature-b'; AdoptionState = 'NotAdopted' }
        )

        $results = Get-FeatureReadiness -LicenseUtilization $license -FeatureAdoption $adoption -FeatureMap $script:mockFeatureMap
        $b = $results | Where-Object { $_.FeatureId -eq 'feature-b' }
        $b.ReadinessState | Should -Be 'Ready'
    }

    It 'Should mark Blocked when prerequisite not adopted' {
        $license = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; IsLicensed = $true }
            [PSCustomObject]@{ FeatureId = 'feature-b'; IsLicensed = $true }
        )
        $adoption = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; AdoptionState = 'NotAdopted' }
            [PSCustomObject]@{ FeatureId = 'feature-b'; AdoptionState = 'NotAdopted' }
        )

        $results = Get-FeatureReadiness -LicenseUtilization $license -FeatureAdoption $adoption -FeatureMap $script:mockFeatureMap
        $b = $results | Where-Object { $_.FeatureId -eq 'feature-b' }
        $b.ReadinessState | Should -Be 'Blocked'
        $b.Blockers | Should -Match 'Feature A'
    }

    It 'Should mark NotLicensed when plan missing' {
        $license = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; IsLicensed = $false }
            [PSCustomObject]@{ FeatureId = 'feature-b'; IsLicensed = $false }
        )
        $adoption = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; AdoptionState = 'NotLicensed' }
            [PSCustomObject]@{ FeatureId = 'feature-b'; AdoptionState = 'NotLicensed' }
        )

        $results = Get-FeatureReadiness -LicenseUtilization $license -FeatureAdoption $adoption -FeatureMap $script:mockFeatureMap
        $a = $results | Where-Object { $_.FeatureId -eq 'feature-a' }
        $a.ReadinessState | Should -Be 'NotLicensed'
        $a.Blockers | Should -Match 'PLAN_A'
    }

    It 'Should return one row per feature' {
        $license = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; IsLicensed = $true }
            [PSCustomObject]@{ FeatureId = 'feature-b'; IsLicensed = $true }
        )
        $adoption = @(
            [PSCustomObject]@{ FeatureId = 'feature-a'; AdoptionState = 'Adopted' }
            [PSCustomObject]@{ FeatureId = 'feature-b'; AdoptionState = 'Adopted' }
        )

        $results = Get-FeatureReadiness -LicenseUtilization $license -FeatureAdoption $adoption -FeatureMap $script:mockFeatureMap
        $results.Count | Should -Be 2
    }
}
