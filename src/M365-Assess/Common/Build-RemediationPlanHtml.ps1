function Build-RemediationPlanHtml {
    <#
    .SYNOPSIS
        Builds the Remediation Action Plan HTML page for the assessment report.
    .DESCRIPTION
        Filters all CIS findings to Fail and Warning status, sorts by risk severity
        (Critical -> High -> Medium -> Low), and renders a collapsible prioritized
        action table with chip filters, dynamic cross-dimension counts, and a
        compact-by-default scrollable viewport with expand/collapse control.
    .PARAMETER Findings
        All CIS findings from the assessment ($allCisFindings).
    .PARAMETER IsQuickScan
        Unused -- reserved for future use; no note is rendered in the page.
    .EXAMPLE
        $remediationPlanHtml = Build-RemediationPlanHtml -Findings $allCisFindings -IsQuickScan:$QuickScan
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [PSCustomObject[]]$Findings = @(),

        [Parameter()]
        [bool]$IsQuickScan = $false
    )

    $actionable = @($Findings | Where-Object { $_.Status -in @('Fail', 'Warning') })

    if ($actionable.Count -eq 0) {
        return @"
<details class='section' id='remediation-plan-section' open>
<summary><h2>Remediation Action Plan</h2></summary>
<div class='remediation-empty'><p>No actionable findings &mdash; all checks passed or were not applicable.</p></div>
</details>
"@
    }

    # Sort: severity priority order, then Section, then CheckId
    $severityOrder = @{ 'Critical' = 0; 'High' = 1; 'Medium' = 2; 'Low' = 3; 'Info' = 4 }
    $sorted = $actionable | Sort-Object -Property @(
        @{ Expression = { if ($severityOrder.ContainsKey($_.RiskSeverity)) { $severityOrder[$_.RiskSeverity] } else { 99 } } }
        @{ Expression = { $_.Section } }
        @{ Expression = { $_.CheckId } }
    )

    $critCount = @($sorted | Where-Object { $_.RiskSeverity -eq 'Critical' }).Count
    $highCount  = @($sorted | Where-Object { $_.RiskSeverity -eq 'High' }).Count
    $medCount   = @($sorted | Where-Object { $_.RiskSeverity -eq 'Medium' }).Count
    $lowCount   = @($sorted | Where-Object { $_.RiskSeverity -eq 'Low' }).Count
    $totalCount = $sorted.Count

    $uniqueSections = @($sorted | Select-Object -ExpandProperty Section -ErrorAction SilentlyContinue | Where-Object { $_ } | Sort-Object -Unique)

    $html = [System.Text.StringBuilder]::new()

    $null = $html.AppendLine("<details class='section' id='remediation-plan-section' open>")
    $null = $html.AppendLine("<summary><h2>Remediation Action Plan</h2></summary>")

    $null = $html.AppendLine("<div class='remediation-header-row'>")

    $null = $html.AppendLine("<div class='remediation-stats'>")
    foreach ($sevEntry in @( @('Critical',$critCount,'critical'), @('High',$highCount,'high'), @('Medium',$medCount,'medium'), @('Low',$lowCount,'low') )) {
        if ($sevEntry[1] -gt 0) {
            $null = $html.AppendLine("<div class='remediation-stat remediation-stat-$($sevEntry[2])'><span class='stat-num'>$($sevEntry[1])</span><span class='stat-label'>$($sevEntry[0])</span></div>")
        }
    }
    $null = $html.AppendLine("</div>")

    if ($uniqueSections.Count -gt 0) {
        $sectionsSorted = $uniqueSections | ForEach-Object {
            $sectionName = $_
            [PSCustomObject]@{ Name = $sectionName; Count = @($sorted | Where-Object { $_.Section -eq $sectionName }).Count }
        } | Sort-Object -Property Count -Descending
        $maxSectionCount = ($sectionsSorted | Measure-Object -Property Count -Maximum).Maximum
        $null = $html.AppendLine("<div class='remediation-section-chart'>")
        $null = $html.AppendLine("<div class='section-chart-title'>By Section</div>")
        foreach ($sec in $sectionsSorted) {
            $pct = if ($maxSectionCount -gt 0) { [int]([Math]::Round(($sec.Count / $maxSectionCount) * 100)) } else { 0 }
            $secEncoded = ConvertTo-HtmlSafe -Text $sec.Name
            $null = $html.AppendLine("<div class='section-bar-row'>")
            $null = $html.AppendLine("<span class='section-bar-label'>$secEncoded</span>")
            $null = $html.AppendLine("<div class='section-bar-track'><div class='section-bar-fill' style='width:$pct%'></div></div>")
            $null = $html.AppendLine("<span class='section-bar-count'>$($sec.Count)</span>")
            $null = $html.AppendLine("</div>")
        }
        $null = $html.AppendLine("</div>")
    }

    $null = $html.AppendLine("</div>")

    $null = $html.AppendLine("<div class='remediation-chip-bar'>")
    $null = $html.AppendLine("<div class='rem-chip-section' id='remSeveritySection'>")
    $null = $html.AppendLine("<span class='rem-filter-label'>Severity:</span>")
    $null = $html.AppendLine("<div class='rem-chip-group' id='remSeverityChips'>")
    foreach ($sevEntry in @( @('Critical',$critCount), @('High',$highCount), @('Medium',$medCount), @('Low',$lowCount) )) {
        $sevName = $sevEntry[0]; $sevCnt = $sevEntry[1]
        if ($sevCnt -gt 0) {
            $null = $html.AppendLine("<label class='fw-checkbox active rem-sev-chip' data-severity='$sevName' onclick='toggleRemChip(this); return false;'><input type='checkbox' checked hidden>$sevName <span class='rem-chip-count'>$sevCnt</span></label>")
        }
    }
    $null = $html.AppendLine("</div>")
    $null = $html.AppendLine("<span class='fw-selector-actions'><button type='button' class='fw-action-btn rem-chips-all' onclick='setAllRemChips(this)'>All</button><button type='button' class='fw-action-btn rem-chips-none' onclick='setAllRemChips(this)'>None</button></span>")
    $null = $html.AppendLine("</div>")

    if ($uniqueSections.Count -gt 0) {
        $null = $html.AppendLine("<div class='rem-chip-section' id='remSectionSection'>")
        $null = $html.AppendLine("<span class='rem-filter-label'>Section:</span>")
        $null = $html.AppendLine("<div class='rem-chip-group' id='remSectionChips'>")
        foreach ($sec in $uniqueSections) {
            $secEncoded = ConvertTo-HtmlSafe -Text $sec
            $secCnt = @($sorted | Where-Object { $_.Section -eq $sec }).Count
            $null = $html.AppendLine("<label class='fw-checkbox active rem-sec-chip' data-section='$secEncoded' onclick='toggleRemChip(this); return false;'><input type='checkbox' checked hidden>$secEncoded <span class='rem-chip-count'>$secCnt</span></label>")
        }
        $null = $html.AppendLine("</div>")
        $null = $html.AppendLine("<span class='fw-selector-actions'><button type='button' class='fw-action-btn rem-chips-all' onclick='setAllRemChips(this)'>All</button><button type='button' class='fw-action-btn rem-chips-none' onclick='setAllRemChips(this)'>None</button></span>")
        $null = $html.AppendLine("</div>")
    }
    $null = $html.AppendLine("</div>")

    $findingWord = if ($totalCount -eq 1) { 'finding' } else { 'findings' }
    $null = $html.AppendLine("<details class='collector-detail' id='remTableDetail' open>")
    $null = $html.AppendLine("<summary><h3>Action Items</h3><span class='row-count' id='remMatchCount'>($totalCount $findingWord)</span></summary>")

    $null = $html.AppendLine("<div class='col-picker-bar'>")
    $null = $html.AppendLine("<button type='button' class='col-picker-toggle'>Columns &#9662;</button>")
    $null = $html.AppendLine("<div class='col-picker-panel' hidden>")
    $null = $html.AppendLine("<label class='col-picker-item'><input type='checkbox' data-col-key='Severity' checked> Severity</label>")
    $null = $html.AppendLine("<label class='col-picker-item'><input type='checkbox' data-col-key='Section' checked> Section</label>")
    $null = $html.AppendLine("<label class='col-picker-item'><input type='checkbox' data-col-key='Check' checked> Check</label>")
    $null = $html.AppendLine("<label class='col-picker-item'><input type='checkbox' data-col-key='CheckId' data-col-default='hidden'> Check ID</label>")
    $null = $html.AppendLine("<label class='col-picker-item'><input type='checkbox' data-col-key='CurrentState' checked> Current State</label>")
    $null = $html.AppendLine("<label class='col-picker-item'><input type='checkbox' data-col-key='Remediation' checked> Remediation</label>")
    $null = $html.AppendLine("</div></div>")

    $null = $html.AppendLine("<div class='table-wrapper remediation-table-wrapper'>")
    $null = $html.AppendLine("<table class='data-table remediation-table' id='remediationTable'>")
    $null = $html.AppendLine("<thead><tr>")
    $null = $html.AppendLine("<th scope='col' data-col-key='Severity'>Severity</th>")
    $null = $html.AppendLine("<th scope='col' data-col-key='Section'>Section</th>")
    $null = $html.AppendLine("<th scope='col' data-col-key='Check'>Check</th>")
    $null = $html.AppendLine("<th scope='col' data-col-key='CheckId' style='display:none'>Check ID</th>")
    $null = $html.AppendLine("<th scope='col' data-col-key='CurrentState'>Current State</th>")
    $null = $html.AppendLine("<th scope='col' data-col-key='Remediation'>Remediation</th>")
    $null = $html.AppendLine("</tr></thead><tbody>")

    foreach ($finding in $sorted) {
        $sev = if ($finding.RiskSeverity) { $finding.RiskSeverity } else { 'Low' }
        $sevClass = switch ($sev) {
            'Critical' { 'remediation-row-critical' }
            'High'     { 'remediation-row-high' }
            'Medium'   { 'remediation-row-medium' }
            default    { 'remediation-row-low' }
        }
        $badgeClass = switch ($sev) {
            'Critical' { 'badge-fail' }
            'High'     { 'badge-warning' }
            'Medium'   { 'badge-review' }
            default    { 'badge-neutral' }
        }
        $sectionEncoded   = ConvertTo-HtmlSafe -Text $finding.Section
        $checkEncoded     = ConvertTo-HtmlSafe -Text $finding.Setting
        $checkIdEncoded   = ConvertTo-HtmlSafe -Text $(if ($finding.CheckId) { $finding.CheckId } else { '' })
        $currentEncoded   = ConvertTo-HtmlSafe -Text $finding.CurrentValue
        $remEncoded       = ConvertTo-HtmlSafe -Text $(if ($finding.Remediation) { $finding.Remediation } else { '' })
        $rationaleEncoded = ConvertTo-HtmlSafe -Text $(if ($finding.ImpactRationale) { $finding.ImpactRationale } else { '' })
        $rationaleHtml    = if ($rationaleEncoded) { "<span class='impact-rationale'>Why it matters: $rationaleEncoded</span>" } else { '' }

        $null = $html.AppendLine("<tr class='$sevClass' data-severity='$sev' data-section='$sectionEncoded'>")
        $null = $html.AppendLine("<td data-col-key='Severity'><span class='badge $badgeClass'>$(ConvertTo-HtmlSafe -Text $sev)</span></td>")
        $null = $html.AppendLine("<td data-col-key='Section'>$sectionEncoded</td>")
        $null = $html.AppendLine("<td data-col-key='Check'>$checkEncoded</td>")
        $null = $html.AppendLine("<td data-col-key='CheckId' style='display:none'>$checkIdEncoded</td>")
        $null = $html.AppendLine("<td data-col-key='CurrentState'>$currentEncoded</td>")
        $null = $html.AppendLine("<td data-col-key='Remediation'><span class='rem-text'>$remEncoded</span><button class='copy-btn' onclick='copyRemediation(this)' title='Copy to clipboard'>&#128203;</button>$rationaleHtml</td>")
        $null = $html.AppendLine("</tr>")
    }

    $null = $html.AppendLine("</tbody></table>")
    $null = $html.AppendLine("</div>")
    $null = $html.AppendLine("<p id='remNoResults' class='no-results' style='display:none'>No findings match the current filter selection.</p>")

    $null = $html.AppendLine("</details>")
    $null = $html.AppendLine("</details>")

    return $html.ToString()
}
