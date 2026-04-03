function Get-LicenseUtilization {
    <#
    .SYNOPSIS
        Cross-references tenant licenses against the feature map.
    .DESCRIPTION
        For each feature in sku-feature-map.json, checks if the tenant has any
        of the required service plans. Returns per-feature license status.
    .PARAMETER TenantLicenses
        Hashtable from Resolve-TenantLicenses with ActiveServicePlans HashSet.
    .PARAMETER FeatureMap
        Parsed sku-feature-map.json object.
    .PARAMETER OutputPath
        Optional CSV output path.
    .EXAMPLE
        Get-LicenseUtilization -TenantLicenses $licenses -FeatureMap $featureMap
        Returns one PSCustomObject per feature with IsLicensed status.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TenantLicenses,

        [Parameter(Mandatory)]
        $FeatureMap,

        [Parameter()]
        [string]$OutputPath
    )

    $categories = @{}
    foreach ($cat in $FeatureMap.categories) {
        $categories[$cat.id] = $cat.name
    }

    $results = foreach ($feature in $FeatureMap.features) {
        $isLicensed = $false
        $sourceSkus = @()

        foreach ($plan in $feature.requiredServicePlans) {
            # "STANDARD" is a sentinel meaning "available in any M365 tenant"
            if ($plan -eq 'STANDARD') {
                $isLicensed = $true
                $sourceSkus += 'E3 Baseline'
                continue
            }
            if ($TenantLicenses.ActiveServicePlans.Contains($plan)) {
                $isLicensed = $true
                $sourceSkus += $plan
            }
        }

        [PSCustomObject]@{
            FeatureId   = $feature.featureId
            FeatureName = $feature.name
            Category    = $categories[$feature.category]
            IsLicensed  = $isLicensed
            SourcePlans = ($sourceSkus -join ', ')
            EffortTier  = $feature.effortTier
            LearnUrl    = $feature.learnUrl
        }
    }

    if ($OutputPath) {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported license utilization ($($results.Count) features) to $OutputPath"
    }
    else {
        Write-Output $results
    }
}
