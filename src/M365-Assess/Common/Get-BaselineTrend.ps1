function Get-BaselineTrend {
    <#
    .SYNOPSIS
        Enumerates saved baselines for a tenant and aggregates per-status counts per snapshot.
    .DESCRIPTION
        Scans the Baselines directory for folders matching the tenant's identity
        suffixes, reads each manifest.json for timestamp + version metadata, and
        counts the Status field across every security-config JSON file in the
        baseline. Returns a chronologically sorted array suitable for trend
        visualisation in the report.

        C1 #780: searches BOTH the legacy '_<TenantId>' folder shape AND the new
        '_<TenantGuid>' shape so a tenant carrying baselines from both pre- and
        post-v2.9.0 runs sees its full history on the trend chart. Folder names
        are unique (timestamp-based), so the union doesn't double-count.
    .PARAMETER BaselinesRoot
        Path to the Baselines directory (typically <OutputFolder>/Baselines).
    .PARAMETER TenantId
        Tenant identifier (typically DefaultDomain). Matches legacy baselines
        saved as '<Label>_<TenantId>'.
    .PARAMETER TenantGuid
        Optional canonical tenant GUID. When supplied, also matches v2.9.0+
        baselines saved as '<Label>_<TenantGuid>'.
    .PARAMETER MaxSnapshots
        Maximum number of most-recent snapshots to return. Defaults to 10 — enough
        context for a visible trend without cluttering the chart. Older snapshots
        are dropped.
    .OUTPUTS
        [PSCustomObject[]] One entry per baseline, sorted chronologically:
          Label, SavedAt, Version, Pass, Warn, Fail, Review, Info, Skipped, Total
    .EXAMPLE
        $trend = Get-BaselineTrend -BaselinesRoot '.\M365-Assessment\Baselines' `
                                    -TenantId 'contoso.com' `
                                    -TenantGuid '11111111-2222-3333-4444-555555555555'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BaselinesRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [string]$TenantGuid = '',

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxSnapshots = 10
    )

    if (-not (Test-Path -Path $BaselinesRoot -PathType Container)) {
        Write-Verbose "Trend: baselines root '$BaselinesRoot' does not exist"
        return @()
    }

    # C1 #780: union of legacy domain suffix + new GUID suffix. Filter against
    # both so post-v2.9.0 baselines (GUID-keyed) and pre-v2.9.0 baselines
    # (TenantId-keyed) both feed the trend chart.
    $safeTenant = $TenantId -replace '[^\w\.\-]', '_'
    # NB: must use ::new() not `New-Object -TypeName ...` here -- the comma in
    # the generic Dictionary type name is parsed as the array operator by
    # PowerShell when bound to -TypeName, producing 'Cannot convert Object[] to
    # System.String required by parameter TypeName' at runtime. ::new() parses
    # the [...] unambiguously as a type literal. Bug surfaced in v2.9.0 when a
    # real tenant ran with -AutoBaseline; HTML report generation died inside
    # the catch in Invoke-M365Assessment.ps1 and silently dropped the report.
    $matchedDirs = [System.Collections.Generic.Dictionary[string, System.IO.DirectoryInfo]]::new()
    foreach ($d in (Get-ChildItem -Path $BaselinesRoot -Directory -Filter "*_${safeTenant}" -ErrorAction SilentlyContinue)) {
        if (-not $matchedDirs.ContainsKey($d.FullName)) { $matchedDirs[$d.FullName] = $d }
    }
    if ($TenantGuid) {
        $safeGuid = $TenantGuid -replace '[^\w\-]', ''
        foreach ($d in (Get-ChildItem -Path $BaselinesRoot -Directory -Filter "*_${safeGuid}" -ErrorAction SilentlyContinue)) {
            if (-not $matchedDirs.ContainsKey($d.FullName)) { $matchedDirs[$d.FullName] = $d }
        }
    }
    $baselineDirs = @($matchedDirs.Values)

    $snapshots = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($dir in $baselineDirs) {
        try {
            $manifestPath = Join-Path -Path $dir.FullName -ChildPath 'manifest.json'
            if (-not (Test-Path -Path $manifestPath)) {
                Write-Verbose "Trend: skipped '$($dir.Name)' — no manifest.json"
                continue
            }
            $manifest = Get-Content -Path $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json

            $counts = @{ pass = 0; warn = 0; fail = 0; review = 0; info = 0; skipped = 0; total = 0 }
            $jsonFiles = Get-ChildItem -Path $dir.FullName -Filter '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'manifest.json' }

            foreach ($jf in $jsonFiles) {
                $rows = Get-Content -Path $jf.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                foreach ($row in @($rows)) {
                    $counts.total++
                    switch ($row.Status) {
                        'Pass'    { $counts.pass++ }
                        'Warning' { $counts.warn++ }
                        'Fail'    { $counts.fail++ }
                        'Review'  { $counts.review++ }
                        'Info'    { $counts.info++ }
                        'Skipped' { $counts.skipped++ }
                    }
                }
            }

            $snapshots.Add([PSCustomObject]@{
                Label   = $manifest.Label
                SavedAt = $manifest.SavedAt
                Version = $manifest.AssessmentVersion
                Pass    = $counts.pass
                Warn    = $counts.warn
                Fail    = $counts.fail
                Review  = $counts.review
                Info    = $counts.info
                Skipped = $counts.skipped
                Total   = $counts.total
            })
        }
        catch {
            Write-Verbose "Trend: skipped baseline '$($dir.Name)': $_"
        }
    }

    @($snapshots | Sort-Object SavedAt | Select-Object -Last $MaxSnapshots)
}
