function Get-FeatureReadiness {
    <#
    .SYNOPSIS
        Checks prerequisites for non-adopted features.
    .PARAMETER LicenseUtilization
        Array from Get-LicenseUtilization.
    .PARAMETER FeatureAdoption
        Array from Get-FeatureAdoption.
    .PARAMETER FeatureMap
        Parsed sku-feature-map.json object.
    .PARAMETER OutputPath
        Optional CSV output path.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$LicenseUtilization,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$FeatureAdoption,

        [Parameter(Mandatory)]
        $FeatureMap,

        [Parameter()]
        [string]$OutputPath
    )

    $categories = @{}
    foreach ($cat in $FeatureMap.categories) { $categories[$cat.id] = $cat.name }

    $licenseLookup = @{}
    foreach ($lic in $LicenseUtilization) { $licenseLookup[$lic.FeatureId] = $lic }

    $adoptionLookup = @{}
    foreach ($adp in $FeatureAdoption) { $adoptionLookup[$adp.FeatureId] = $adp }

    $featureNameLookup = @{}
    foreach ($f in $FeatureMap.features) { $featureNameLookup[$f.featureId] = $f.name }

    $results = foreach ($feature in $FeatureMap.features) {
        $lic = $licenseLookup[$feature.featureId]
        $blockers = @()

        if (-not $lic -or -not $lic.IsLicensed) {
            $planNames = $feature.requiredServicePlans -join ', '
            [PSCustomObject]@{
                FeatureId      = $feature.featureId
                FeatureName    = $feature.name
                Category       = $categories[$feature.category]
                ReadinessState = 'NotLicensed'
                Blockers       = "Requires $planNames"
                EffortTier     = $feature.effortTier
                LearnUrl       = $feature.learnUrl
            }
            continue
        }

        # Check prerequisites
        foreach ($prereqId in $feature.prerequisites) {
            $prereqAdoption = $adoptionLookup[$prereqId]
            if (-not $prereqAdoption -or $prereqAdoption.AdoptionState -notin @('Adopted', 'Partial')) {
                $prereqName = $featureNameLookup[$prereqId]
                if (-not $prereqName) { $prereqName = $prereqId }
                $blockers += "Requires $prereqName"
            }
        }

        $state = if ($blockers.Count -gt 0) { 'Blocked' } else { 'Ready' }

        [PSCustomObject]@{
            FeatureId      = $feature.featureId
            FeatureName    = $feature.name
            Category       = $categories[$feature.category]
            ReadinessState = $state
            Blockers       = ($blockers -join '; ')
            EffortTier     = $feature.effortTier
            LearnUrl       = $feature.learnUrl
        }
    }

    if ($OutputPath) {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported feature readiness ($($results.Count) features) to $OutputPath"
    }
    else {
        Write-Output $results
    }
}
