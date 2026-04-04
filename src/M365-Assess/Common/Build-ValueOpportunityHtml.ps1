function Build-ValueOpportunityHtml {
    <#
    .SYNOPSIS
        Renders the Value Opportunity report page from analysis results.
    .DESCRIPTION
        Generates HTML for the Value Opportunity section including hero panel
        with adoption donut chart, category breakdown bars, quick wins table,
        phased roadmap, and optional not-licensed upsell section. Uses
        StringBuilder for efficient string building and follows existing report
        HTML conventions.
    .PARAMETER Analysis
        Hashtable from Measure-ValueOpportunity containing OverallAdoptionPct,
        LicensedFeatureCount, AdoptedFeatureCount, PartialFeatureCount, GapCount,
        CategoryBreakdown, Roadmap, GapMatrix, and NotLicensedFeatures.
    .EXAMPLE
        Build-ValueOpportunityHtml -Analysis $voAnalysis
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Analysis
    )

    $html = [System.Text.StringBuilder]::new()

    $overallPct = $Analysis.OverallAdoptionPct
    $licensedCount = $Analysis.LicensedFeatureCount
    $adoptedCount = $Analysis.AdoptedFeatureCount + $Analysis.PartialFeatureCount
    $gapCount = $Analysis.GapCount

    # Determine donut CSS class based on adoption percentage
    $donutClass = if ($overallPct -ge 75) { 'success' } elseif ($overallPct -ge 50) { 'warning' } else { 'danger' }

    # ------------------------------------------------------------------
    # Section wrapper
    # ------------------------------------------------------------------
    $null = $html.AppendLine("<details class='section' open>")
    $null = $html.AppendLine("<summary><h2>Value Opportunity</h2></summary>")

    # ------------------------------------------------------------------
    # Hero panel
    # ------------------------------------------------------------------
    $null = $html.AppendLine("<div class='value-hero'>")

    # Donut chart
    $null = $html.AppendLine("<div class='value-hero-donut'>")
    if (Get-Command -Name 'Get-SvgDonut' -ErrorAction SilentlyContinue) {
        $donutSvg = Get-SvgDonut -Percentage $overallPct -CssClass $donutClass -Size 120 -StrokeWidth 10
        $null = $html.AppendLine($donutSvg)
    } else {
        $null = $html.AppendLine("<div style='width:120px;height:120px;border-radius:50%;display:flex;align-items:center;justify-content:center;border:10px solid var(--m365a-border);font-size:20pt;font-weight:700;'>$overallPct%</div>")
    }
    $null = $html.AppendLine("</div>")

    # Stat cards
    $null = $html.AppendLine("<div>")
    $null = $html.AppendLine("<div class='value-hero-stats'>")

    $null = $html.AppendLine("<div class='value-stat-card'>")
    $null = $html.AppendLine("<div class='value-stat-value'>$licensedCount</div>")
    $null = $html.AppendLine("<div class='value-stat-label'>Licensed Features</div>")
    $null = $html.AppendLine("</div>")

    $null = $html.AppendLine("<div class='value-stat-card'>")
    $null = $html.AppendLine("<div class='value-stat-value'>$adoptedCount</div>")
    $null = $html.AppendLine("<div class='value-stat-label'>Adopted</div>")
    $null = $html.AppendLine("</div>")

    $null = $html.AppendLine("<div class='value-stat-card'>")
    $null = $html.AppendLine("<div class='value-stat-value'>$gapCount</div>")
    $null = $html.AppendLine("<div class='value-stat-label'>Gaps</div>")
    $null = $html.AppendLine("</div>")

    $null = $html.AppendLine("</div>")

    # Summary text
    $null = $html.AppendLine("<div class='value-hero-summary'>Your organization uses $adoptedCount of $licensedCount licensed features ($overallPct%)</div>")
    $null = $html.AppendLine("</div>")
    $null = $html.AppendLine("</div>")

    # ------------------------------------------------------------------
    # Category breakdown bars
    # ------------------------------------------------------------------
    $categoryBreakdown = $Analysis.CategoryBreakdown
    if ($categoryBreakdown -and $categoryBreakdown.Count -gt 0) {
        $null = $html.AppendLine("<div class='value-categories'>")
        $null = $html.AppendLine("<h3>Category Breakdown</h3>")

        foreach ($cat in $categoryBreakdown) {
            $catName = ConvertTo-HtmlSafe $cat.Category
            $catLicensed = [int]$cat.Licensed
            $catPct = [int]$cat.Pct

            if ($catLicensed -eq 0) {
                $adoptedWidth = 0
                $partialWidth = 0
                $gapWidth = 0
            } else {
                $adoptedWidth = [int][Math]::Round($cat.Adopted / $catLicensed * 100, 0, [MidpointRounding]::AwayFromZero)
                $partialWidth = [int][Math]::Round($cat.Partial / $catLicensed * 100, 0, [MidpointRounding]::AwayFromZero)
                $gapWidth = 100 - $adoptedWidth - $partialWidth
                if ($gapWidth -lt 0) { $gapWidth = 0 }
            }

            $null = $html.AppendLine("<div class='value-category-row'>")
            $null = $html.AppendLine("<div class='value-category-label'>$catName</div>")
            $null = $html.AppendLine("<div class='value-category-bar'>")
            $null = $html.AppendLine("<div class='value-bar-fill value-bar-adopted' style='width: $adoptedWidth%'></div>")
            $null = $html.AppendLine("<div class='value-bar-fill value-bar-partial' style='width: $partialWidth%'></div>")
            $null = $html.AppendLine("<div class='value-bar-fill value-bar-gap' style='width: $gapWidth%'></div>")
            $null = $html.AppendLine("</div>")
            $null = $html.AppendLine("<div class='value-category-pct'>$catPct%</div>")
            $null = $html.AppendLine("</div>")
        }

        $null = $html.AppendLine("</div>")
    }

    # ------------------------------------------------------------------
    # Quick Wins table
    # ------------------------------------------------------------------
    $quickWins = @($Analysis.Roadmap['Quick Win'])
    if ($quickWins.Count -gt 0) {
        $null = $html.AppendLine("<div class='callout callout-tip'><div class='callout-title'><span class='callout-icon'>&#128161;</span> Quick Wins</div><div class='callout-body'>These features are already licensed and require minimal effort to enable.</div></div>")
        $null = $html.AppendLine("<table class='data-table'>")
        $null = $html.AppendLine("<thead><tr><th>Feature</th><th>Category</th><th>Score</th><th>Learn</th></tr></thead>")
        $null = $html.AppendLine("<tbody>")

        foreach ($item in $quickWins) {
            $featureName = ConvertTo-HtmlSafe $item.FeatureName
            $category = ConvertTo-HtmlSafe $item.Category
            $score = [int]$item.AdoptionScore
            $learnLink = ''
            if ($item.LearnUrl) {
                $safeUrl = ConvertTo-HtmlSafe $item.LearnUrl
                $learnLink = "<a href='$safeUrl' target='_blank' rel='noopener' class='value-learn-link'>Learn more</a>"
            }
            $null = $html.AppendLine("<tr><td>$featureName</td><td>$category</td><td>$score</td><td>$learnLink</td></tr>")
        }

        $null = $html.AppendLine("</tbody></table>")
    }

    # ------------------------------------------------------------------
    # Full Roadmap (three collapsible tiers)
    # ------------------------------------------------------------------
    $roadmapTiers = @(
        @{ Key = 'Quick Win'; Label = 'Quick Wins'; Icon = '&#9889;' }
        @{ Key = 'Medium';    Label = 'Medium Effort'; Icon = '&#9881;' }
        @{ Key = 'Strategic'; Label = 'Strategic'; Icon = '&#127919;' }
    )

    $hasRoadmap = $false
    foreach ($tier in $roadmapTiers) {
        if ($Analysis.Roadmap[$tier.Key] -and $Analysis.Roadmap[$tier.Key].Count -gt 0) {
            $hasRoadmap = $true
            break
        }
    }

    if ($hasRoadmap) {
        $null = $html.AppendLine("<h3>Adoption Roadmap</h3>")

        foreach ($tier in $roadmapTiers) {
            $tierItems = @($Analysis.Roadmap[$tier.Key])
            if ($tierItems.Count -eq 0) { continue }

            $tierLabel = $tier.Label
            $tierIcon = $tier.Icon
            $isQuickWin = $tier.Key -eq 'Quick Win'

            $null = $html.AppendLine("<details class='value-roadmap-section'" + $(if ($isQuickWin) { ' open' } else { '' }) + ">")
            $null = $html.AppendLine("<summary><strong>$tierIcon $tierLabel ($($tierItems.Count))</strong></summary>")
            $null = $html.AppendLine("<table class='data-table'>")
            $null = $html.AppendLine("<thead><tr><th>Feature</th><th>Category</th><th>Adoption Score</th><th>Readiness</th><th>Blockers</th><th>Learn</th></tr></thead>")
            $null = $html.AppendLine("<tbody>")

            foreach ($item in $tierItems) {
                $featureName = ConvertTo-HtmlSafe $item.FeatureName
                $category = ConvertTo-HtmlSafe $item.Category
                $score = [int]$item.AdoptionScore
                $readiness = ConvertTo-HtmlSafe $item.ReadinessState
                $blockers = ConvertTo-HtmlSafe $item.Blockers
                $learnLink = ''
                if ($item.LearnUrl) {
                    $safeUrl = ConvertTo-HtmlSafe $item.LearnUrl
                    $learnLink = "<a href='$safeUrl' target='_blank' rel='noopener' class='value-learn-link'>Learn more</a>"
                }
                $null = $html.AppendLine("<tr><td>$featureName</td><td>$category</td><td>$score</td><td>$readiness</td><td>$blockers</td><td>$learnLink</td></tr>")
            }

            $null = $html.AppendLine("</tbody></table>")
            $null = $html.AppendLine("</details>")
        }
    }

    # ------------------------------------------------------------------
    # Not Licensed section (optional, collapsed)
    # ------------------------------------------------------------------
    $notLicensed = $Analysis.NotLicensedFeatures
    if ($notLicensed -and $notLicensed.Count -gt 0) {
        $null = $html.AppendLine("<details class='value-roadmap-section'>")
        $null = $html.AppendLine("<summary><strong>&#128274; Not Licensed ($($notLicensed.Count) features)</strong></summary>")
        $null = $html.AppendLine("<div class='callout callout-info'><div class='callout-title'><span class='callout-icon'>&#9432;</span> Upsell Opportunities</div><div class='callout-body'>These features are available in higher-tier licenses but are not currently licensed in your tenant.</div></div>")
        $null = $html.AppendLine("<table class='data-table'>")
        $null = $html.AppendLine("<thead><tr><th>Feature</th><th>Category</th><th>Effort Tier</th><th>Required Service Plans</th></tr></thead>")
        $null = $html.AppendLine("<tbody>")

        foreach ($item in $notLicensed) {
            $featureName = ConvertTo-HtmlSafe $item.FeatureName
            $category = ConvertTo-HtmlSafe $item.Category
            $effortTier = ConvertTo-HtmlSafe $item.EffortTier
            $plans = if ($item.RequiredServicePlans -and $item.RequiredServicePlans.Count -gt 0) {
                ConvertTo-HtmlSafe ($item.RequiredServicePlans -join ', ')
            } else { '' }
            $null = $html.AppendLine("<tr><td>$featureName</td><td>$category</td><td>$effortTier</td><td>$plans</td></tr>")
        }

        $null = $html.AppendLine("</tbody></table>")
        $null = $html.AppendLine("</details>")
    }

    # Close section
    $null = $html.AppendLine("</details>")

    return $html.ToString()
}
