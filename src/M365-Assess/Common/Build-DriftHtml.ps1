function Build-DriftHtml {
    <#
    .SYNOPSIS
        Builds the Drift Analysis HTML section for the assessment report.
    .DESCRIPTION
        Renders a self-contained report page showing all changes detected between
        the current assessment and a named baseline. Changes are classified as
        Regressed, Improved, Modified, New, or Removed and colour-coded.
    .PARAMETER DriftReport
        Array of drift result objects from Compare-AssessmentBaseline.
    .PARAMETER BaselineLabel
        Human-readable label of the baseline that was compared (e.g. 'Q1-2026').
    .PARAMETER BaselineTimestamp
        ISO 8601 timestamp from the baseline metadata, shown in the section header.
    .EXAMPLE
        $driftHtml = Build-DriftHtml -DriftReport $driftReport -BaselineLabel 'Q1-2026' -BaselineTimestamp '2026-01-01T00:00:00Z'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$DriftReport,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BaselineLabel,

        [Parameter()]
        [string]$BaselineTimestamp = ''
    )

    $html = [System.Text.StringBuilder]::new()

    $regressed  = @($DriftReport | Where-Object { $_.ChangeType -eq 'Regressed' })
    $improved   = @($DriftReport | Where-Object { $_.ChangeType -eq 'Improved' })
    $modified   = @($DriftReport | Where-Object { $_.ChangeType -eq 'Modified' })
    $newChecks  = @($DriftReport | Where-Object { $_.ChangeType -eq 'New' })
    $removed    = @($DriftReport | Where-Object { $_.ChangeType -eq 'Removed' })

    $totalChanged = $DriftReport.Count
    $timestampDisplay = if ($BaselineTimestamp) {
        try { ([datetime]$BaselineTimestamp).ToString('yyyy-MM-dd HH:mm') } catch { $BaselineTimestamp }
    } else { '' }

    $null = $html.AppendLine("<div class='report-page' data-page='drift-analysis' id='drift-analysis'>")
    $null = $html.AppendLine("<details class='section' id='drift-analysis-section' open>")
    $null = $html.AppendLine("<summary><h2>Drift Analysis</h2></summary>")

    # Header: baseline info + stat tiles
    $null = $html.AppendLine("<div class='drift-header'>")
    $null = $html.AppendLine("<div class='drift-baseline-info'>")
    $null = $html.AppendLine("<span class='drift-label-badge'>Baseline: $([System.Net.WebUtility]::HtmlEncode($BaselineLabel))</span>")
    if ($timestampDisplay) {
        $null = $html.AppendLine("<span class='drift-timestamp'>Captured: $timestampDisplay</span>")
    }
    $null = $html.AppendLine("</div>")

    # Stat tiles
    $null = $html.AppendLine("<div class='drift-stats'>")
    if ($regressed.Count -gt 0) {
        $null = $html.AppendLine("<div class='drift-stat drift-stat-regressed'><span class='stat-num'>$($regressed.Count)</span><span class='stat-label'>Regressed</span></div>")
    }
    if ($improved.Count -gt 0) {
        $null = $html.AppendLine("<div class='drift-stat drift-stat-improved'><span class='stat-num'>$($improved.Count)</span><span class='stat-label'>Improved</span></div>")
    }
    if ($modified.Count -gt 0) {
        $null = $html.AppendLine("<div class='drift-stat drift-stat-modified'><span class='stat-num'>$($modified.Count)</span><span class='stat-label'>Modified</span></div>")
    }
    if ($newChecks.Count -gt 0) {
        $null = $html.AppendLine("<div class='drift-stat drift-stat-new'><span class='stat-num'>$($newChecks.Count)</span><span class='stat-label'>New</span></div>")
    }
    if ($removed.Count -gt 0) {
        $null = $html.AppendLine("<div class='drift-stat drift-stat-removed'><span class='stat-num'>$($removed.Count)</span><span class='stat-label'>Removed</span></div>")
    }
    $null = $html.AppendLine("</div>") # drift-stats
    $null = $html.AppendLine("</div>") # drift-header

    if ($totalChanged -eq 0) {
        $null = $html.AppendLine("<div class='drift-no-changes'><p>No changes detected since baseline <strong>$([System.Net.WebUtility]::HtmlEncode($BaselineLabel))</strong>. All assessed checks match their baseline values.</p></div>")
        $null = $html.AppendLine("</details></div>")
        return $html.ToString()
    }

    # Sort: Regressed first, then Improved, Modified, New, Removed
    $sortOrder = @{ Regressed = 0; Improved = 1; Modified = 2; New = 3; Removed = 4 }
    $sorted = $DriftReport | Sort-Object -Property @{
        Expression = { $sortOrder[$_.ChangeType] }
    }, Section, Setting

    $null = $html.AppendLine("<details class='collector-detail' open>")
    $null = $html.AppendLine("<summary><h3>Changed Checks</h3><span class='row-count'>($totalChanged changes)</span></summary>")
    $null = $html.AppendLine("<div class='table-wrapper'>")
    $null = $html.AppendLine("<table class='data-table drift-table'>")
    $null = $html.AppendLine("<thead><tr>")
    $null = $html.AppendLine("<th>Change</th><th>Section</th><th>Check</th><th>Before</th><th>After</th>")
    $null = $html.AppendLine("</tr></thead><tbody>")

    foreach ($row in $sorted) {
        $changeType = $row.ChangeType
        $rowClass = switch ($changeType) {
            'Regressed' { 'drift-row-regressed' }
            'Improved'  { 'drift-row-improved' }
            'Modified'  { 'drift-row-modified' }
            'New'       { 'drift-row-new' }
            'Removed'   { 'drift-row-removed' }
            default     { '' }
        }
        $chipClass = switch ($changeType) {
            'Regressed' { 'drift-chip-regressed' }
            'Improved'  { 'drift-chip-improved' }
            'Modified'  { 'drift-chip-modified' }
            'New'       { 'drift-chip-new' }
            'Removed'   { 'drift-chip-removed' }
            default     { '' }
        }

        $settingEncoded  = [System.Net.WebUtility]::HtmlEncode($row.Setting)
        $sectionEncoded  = [System.Net.WebUtility]::HtmlEncode($row.Section)
        $prevStatusEnc   = [System.Net.WebUtility]::HtmlEncode($row.PreviousStatus)
        $currStatusEnc   = [System.Net.WebUtility]::HtmlEncode($row.CurrentStatus)
        $prevValueEnc    = [System.Net.WebUtility]::HtmlEncode($row.PreviousValue)
        $currValueEnc    = [System.Net.WebUtility]::HtmlEncode($row.CurrentValue)

        # Before / after cell content: show status if changed, else show value
        $beforeCell = if ($prevStatusEnc) { "<span class='badge badge-neutral'>$prevStatusEnc</span>" } else { '<span class="drift-empty">&#8212;</span>' }
        $afterCell  = if ($currStatusEnc) { "<span class='badge badge-neutral'>$currStatusEnc</span>" } else { '<span class="drift-empty">&#8212;</span>' }

        # If status unchanged but value changed, show the value instead
        if ($row.PreviousStatus -eq $row.CurrentStatus -and ($prevValueEnc -or $currValueEnc)) {
            $beforeCell = "<span class='drift-value'>$prevValueEnc</span>"
            $afterCell  = "<span class='drift-value'>$currValueEnc</span>"
        }

        $null = $html.AppendLine("<tr class='$rowClass'>")
        $null = $html.AppendLine("<td><span class='drift-chip $chipClass'>$changeType</span></td>")
        $null = $html.AppendLine("<td>$sectionEncoded</td>")
        $null = $html.AppendLine("<td>$settingEncoded</td>")
        $null = $html.AppendLine("<td>$beforeCell</td>")
        $null = $html.AppendLine("<td>$afterCell</td>")
        $null = $html.AppendLine("</tr>")
    }

    $null = $html.AppendLine("</tbody></table>")
    $null = $html.AppendLine("</div>") # table-wrapper
    $null = $html.AppendLine("</details>") # collector-detail
    $null = $html.AppendLine("</details>") # section
    $null = $html.AppendLine("</div>") # report-page

    return $html.ToString()
}
