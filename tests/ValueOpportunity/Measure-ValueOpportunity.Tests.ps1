BeforeAll {
    . "$PSScriptRoot/../../src/M365-Assess/ValueOpportunity/Measure-ValueOpportunity.ps1"
}

Describe 'Measure-ValueOpportunity' {
    BeforeAll {
        $script:mockFeatureMap = @{
            categories = @(
                @{ id = 'identity-access'; name = 'Identity & Access'; icon = 'Person' }
                @{ id = 'email-security'; name = 'Email Security'; icon = 'Shield' }
            )
            features = @(
                @{ featureId = 'f1'; name = 'F1'; category = 'identity-access'; effortTier = 'Quick Win'; requiredServicePlans = @('STANDARD') }
                @{ featureId = 'f2'; name = 'F2'; category = 'identity-access'; effortTier = 'Medium'; requiredServicePlans = @('PLAN_A') }
                @{ featureId = 'f3'; name = 'F3'; category = 'email-security'; effortTier = 'Strategic'; requiredServicePlans = @('PLAN_B') }
                @{ featureId = 'f4'; name = 'F4'; category = 'email-security'; effortTier = 'Quick Win'; requiredServicePlans = @('STANDARD') }
            )
        }
        $script:mockLicense = @(
            [PSCustomObject]@{ FeatureId = 'f1'; IsLicensed = $true }
            [PSCustomObject]@{ FeatureId = 'f2'; IsLicensed = $true }
            [PSCustomObject]@{ FeatureId = 'f3'; IsLicensed = $false }
            [PSCustomObject]@{ FeatureId = 'f4'; IsLicensed = $true }
        )
        $script:mockAdoption = @(
            [PSCustomObject]@{ FeatureId = 'f1'; FeatureName = 'F1'; Category = 'Identity & Access'; AdoptionState = 'Adopted'; AdoptionScore = 100 }
            [PSCustomObject]@{ FeatureId = 'f2'; FeatureName = 'F2'; Category = 'Identity & Access'; AdoptionState = 'NotAdopted'; AdoptionScore = 0 }
            [PSCustomObject]@{ FeatureId = 'f3'; FeatureName = 'F3'; Category = 'Email Security'; AdoptionState = 'NotLicensed'; AdoptionScore = 0 }
            [PSCustomObject]@{ FeatureId = 'f4'; FeatureName = 'F4'; Category = 'Email Security'; AdoptionState = 'Partial'; AdoptionScore = 50 }
        )
        $script:mockReadiness = @(
            [PSCustomObject]@{ FeatureId = 'f1'; FeatureName = 'F1'; ReadinessState = 'Ready'; EffortTier = 'Quick Win'; Blockers = ''; LearnUrl = 'https://test/f1'; Category = 'Identity & Access' }
            [PSCustomObject]@{ FeatureId = 'f2'; FeatureName = 'F2'; ReadinessState = 'Ready'; EffortTier = 'Medium'; Blockers = ''; LearnUrl = 'https://test/f2'; Category = 'Identity & Access' }
            [PSCustomObject]@{ FeatureId = 'f3'; FeatureName = 'F3'; ReadinessState = 'NotLicensed'; EffortTier = 'Strategic'; Blockers = 'Requires PLAN_B'; LearnUrl = 'https://test/f3'; Category = 'Email Security' }
            [PSCustomObject]@{ FeatureId = 'f4'; FeatureName = 'F4'; ReadinessState = 'Ready'; EffortTier = 'Quick Win'; Blockers = ''; LearnUrl = 'https://test/f4'; Category = 'Email Security' }
        )
    }

    It 'Should calculate overall adoption percentage from licensed features' {
        $result = Measure-ValueOpportunity -LicenseUtilization $script:mockLicense -FeatureAdoption $script:mockAdoption -FeatureReadiness $script:mockReadiness -FeatureMap $script:mockFeatureMap
        # 3 licensed features: f1 (Adopted), f2 (NotAdopted), f4 (Partial)
        # 2 of 3 are adopted/partial = 67%
        $result.OverallAdoptionPct | Should -Be 67
    }

    It 'Should count licensed and adopted features' {
        $result = Measure-ValueOpportunity -LicenseUtilization $script:mockLicense -FeatureAdoption $script:mockAdoption -FeatureReadiness $script:mockReadiness -FeatureMap $script:mockFeatureMap
        $result.LicensedFeatureCount | Should -Be 3
        $result.AdoptedFeatureCount | Should -Be 1
        $result.PartialFeatureCount | Should -Be 1
        $result.GapCount | Should -Be 1
    }

    It 'Should produce category breakdown' {
        $result = Measure-ValueOpportunity -LicenseUtilization $script:mockLicense -FeatureAdoption $script:mockAdoption -FeatureReadiness $script:mockReadiness -FeatureMap $script:mockFeatureMap
        $result.CategoryBreakdown.Count | Should -Be 2
        $idCat = $result.CategoryBreakdown | Where-Object { $_.Category -eq 'Identity & Access' }
        $idCat.Licensed | Should -Be 2
        $idCat.Adopted | Should -Be 1
    }

    It 'Should produce roadmap with only licensed not-adopted features' {
        $result = Measure-ValueOpportunity -LicenseUtilization $script:mockLicense -FeatureAdoption $script:mockAdoption -FeatureReadiness $script:mockReadiness -FeatureMap $script:mockFeatureMap
        # f2 is licensed + NotAdopted + Medium effort
        $result.Roadmap['Medium'].Count | Should -Be 1
        $result.Roadmap['Medium'][0].FeatureId | Should -Be 'f2'
    }

    It 'Should list not-licensed features separately' {
        $result = Measure-ValueOpportunity -LicenseUtilization $script:mockLicense -FeatureAdoption $script:mockAdoption -FeatureReadiness $script:mockReadiness -FeatureMap $script:mockFeatureMap
        $result.NotLicensedFeatures.Count | Should -Be 1
        $result.NotLicensedFeatures[0].FeatureId | Should -Be 'f3'
    }

    It 'Should handle zero licensed features gracefully' {
        $emptyLicense = @(
            [PSCustomObject]@{ FeatureId = 'f1'; IsLicensed = $false }
            [PSCustomObject]@{ FeatureId = 'f2'; IsLicensed = $false }
            [PSCustomObject]@{ FeatureId = 'f3'; IsLicensed = $false }
            [PSCustomObject]@{ FeatureId = 'f4'; IsLicensed = $false }
        )
        $allNotLicensed = @(
            [PSCustomObject]@{ FeatureId = 'f1'; FeatureName = 'F1'; Category = 'Identity & Access'; AdoptionState = 'NotLicensed'; AdoptionScore = 0 }
            [PSCustomObject]@{ FeatureId = 'f2'; FeatureName = 'F2'; Category = 'Identity & Access'; AdoptionState = 'NotLicensed'; AdoptionScore = 0 }
            [PSCustomObject]@{ FeatureId = 'f3'; FeatureName = 'F3'; Category = 'Email Security'; AdoptionState = 'NotLicensed'; AdoptionScore = 0 }
            [PSCustomObject]@{ FeatureId = 'f4'; FeatureName = 'F4'; Category = 'Email Security'; AdoptionState = 'NotLicensed'; AdoptionScore = 0 }
        )
        $result = Measure-ValueOpportunity -LicenseUtilization $emptyLicense -FeatureAdoption $allNotLicensed -FeatureReadiness $script:mockReadiness -FeatureMap $script:mockFeatureMap
        $result.OverallAdoptionPct | Should -Be 0
        $result.LicensedFeatureCount | Should -Be 0
    }
}
