function Compare-M365Baseline {
    <#
    .SYNOPSIS
        Compares two saved baseline snapshots to produce a drift report without re-running an assessment.
    .DESCRIPTION
        Reads the security-config JSON files from two saved baseline folders and produces
        a drift HTML report showing Improved, Regressed, Modified, New, and Removed checks
        between the two points in time.

        When -BaselineB is omitted the most recent saved baseline for the tenant is used as
        the "current" reference, allowing you to compare any historical baseline against the
        closest subsequent one.
    .PARAMETER BaselineA
        Label of the earlier (reference) baseline to compare from.
    .PARAMETER BaselineB
        Label of the later baseline to compare to. Defaults to the most recent saved baseline
        for the tenant.
    .PARAMETER TenantId
        Tenant identifier used to locate the baseline folders under
        <OutputFolder>/Baselines/<Label>_<TenantId>/.
    .PARAMETER OutputFolder
        Root output folder (parent of Baselines/). Defaults to the current directory.
    .PARAMETER OutputPath
        Path for the generated HTML report. Defaults to _Drift-<BaselineA>-vs-<BaselineB>.html
        in the OutputFolder.
    .EXAMPLE
        PS> Compare-M365Baseline -BaselineA 'Q1-2026' -BaselineB 'Q2-2026' -TenantId 'contoso.com'

        Generates a drift report between two quarterly baselines.
    .EXAMPLE
        PS> Compare-M365Baseline -BaselineA 'Q1-2026' -TenantId 'contoso.com'

        Compares Q1-2026 against the most recent other saved baseline for the tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BaselineA,

        [Parameter()]
        [string]$BaselineB,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [string]$OutputFolder = '.',

        [Parameter()]
        [string]$OutputPath
    )

    $safeTenant = $TenantId -replace '[^\w\.\-]', '_'
    $safeA = $BaselineA -replace '[^\w\-]', '_'
    $baselinesRoot = Join-Path -Path $OutputFolder -ChildPath 'Baselines'

    $folderA = Join-Path -Path $baselinesRoot -ChildPath "${safeA}_${safeTenant}"
    if (-not (Test-Path -Path $folderA -PathType Container)) {
        Write-Error "Baseline '$BaselineA' not found at '$folderA'"
        return
    }

    # Resolve BaselineB: explicit label, or most recent other baseline for tenant
    if ($BaselineB) {
        $safeB = $BaselineB -replace '[^\w\-]', '_'
        $folderB = Join-Path -Path $baselinesRoot -ChildPath "${safeB}_${safeTenant}"
        if (-not (Test-Path -Path $folderB -PathType Container)) {
            Write-Error "Baseline '$BaselineB' not found at '$folderB'"
            return
        }
        $labelB = $BaselineB
    }
    else {
        $otherFolders = Get-ChildItem -Path $baselinesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*_${safeTenant}" -and $_.Name -ne "${safeA}_${safeTenant}" } |
            Sort-Object LastWriteTime -Descending
        if (-not $otherFolders) {
            Write-Error "No other baselines found for tenant '$TenantId' to compare against."
            return
        }
        $folderB = $otherFolders[0].FullName
        $labelB  = $otherFolders[0].Name -replace "_${safeTenant}$", ''
    }

    # Read manifest version info for cross-version detection
    $regVersionA = ''
    $regVersionB = ''
    $timestampA  = ''
    $timestampB  = ''
    foreach ($info in @(
        @{ Folder = $folderA; VersionRef = [ref]$regVersionA; TsRef = [ref]$timestampA }
        @{ Folder = $folderB; VersionRef = [ref]$regVersionB; TsRef = [ref]$timestampB }
    )) {
        $mPath = Join-Path -Path $info.Folder -ChildPath 'manifest.json'
        if (Test-Path -Path $mPath) {
            try {
                $m = Get-Content -Path $mPath -Raw | ConvertFrom-Json
                $info.VersionRef.Value = $m.RegistryVersion
                $info.TsRef.Value     = $m.SavedAt
            }
            catch { Write-Verbose "Compare-M365Baseline: could not read manifest at '$mPath': $_" }
        }
    }

    $crossVersion = $regVersionA -and $regVersionB -and ($regVersionA -ne $regVersionB)

    # Build check maps from baseline JSON files
    $mapA = @{}
    $mapB = @{}
    foreach ($pair in @(
        @{ Folder = $folderA; Map = [ref]$mapA }
        @{ Folder = $folderB; Map = [ref]$mapB }
    )) {
        Get-ChildItem -Path $pair.Folder -Filter '*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'manifest.json' } |
            ForEach-Object {
                try {
                    $rows = Get-Content -Path $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                    foreach ($row in $rows) {
                        if ($row.CheckId) { $pair.Map.Value[$row.CheckId] = $row }
                    }
                }
                catch { Write-Warning "Could not load '$($_.Name)': $_" }
            }
    }

    $sharedIds = if ($crossVersion) {
        $mapB.Keys | Where-Object { $mapA.ContainsKey($_) }
    } else {
        $mapB.Keys
    }

    $passStatuses = @('Pass')
    $failStatuses = @('Fail', 'Warning')
    $driftResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($checkId in $sharedIds) {
        $current  = $mapB[$checkId]
        $baseline = $mapA[$checkId]

        if (-not $baseline) {
            $driftResults.Add([PSCustomObject]@{
                CheckId        = $checkId
                Setting        = $current.Setting
                Category       = $current.Category
                Section        = ''
                ChangeType     = 'New'
                PreviousStatus = ''
                CurrentStatus  = $current.Status
                PreviousValue  = ''
                CurrentValue   = $current.CurrentValue
            })
            continue
        }

        if ($baseline.Status -eq $current.Status -and $baseline.CurrentValue -eq $current.CurrentValue) {
            continue
        }

        $changeType = if ($baseline.Status -in $failStatuses -and $current.Status -in $passStatuses) {
            'Improved'
        } elseif ($baseline.Status -in $passStatuses -and $current.Status -in $failStatuses) {
            'Regressed'
        } else {
            'Modified'
        }

        $driftResults.Add([PSCustomObject]@{
            CheckId        = $checkId
            Setting        = $current.Setting
            Category       = $current.Category
            Section        = ''
            ChangeType     = $changeType
            PreviousStatus = $baseline.Status
            CurrentStatus  = $current.Status
            PreviousValue  = $baseline.CurrentValue
            CurrentValue   = $current.CurrentValue
        })
    }

    if ($crossVersion) {
        foreach ($checkId in $mapB.Keys) {
            if (-not $mapA.ContainsKey($checkId)) {
                $row = $mapB[$checkId]
                $driftResults.Add([PSCustomObject]@{
                    CheckId        = $checkId
                    Setting        = $row.Setting
                    Category       = $row.Category
                    Section        = ''
                    ChangeType     = 'SchemaNew'
                    PreviousStatus = ''
                    CurrentStatus  = $row.Status
                    PreviousValue  = ''
                    CurrentValue   = $row.CurrentValue
                })
            }
        }
        foreach ($checkId in $mapA.Keys) {
            if (-not $mapB.ContainsKey($checkId)) {
                $row = $mapA[$checkId]
                $driftResults.Add([PSCustomObject]@{
                    CheckId        = $checkId
                    Setting        = $row.Setting
                    Category       = $row.Category
                    Section        = ''
                    ChangeType     = 'SchemaRemoved'
                    PreviousStatus = $row.Status
                    CurrentStatus  = ''
                    PreviousValue  = $row.CurrentValue
                    CurrentValue   = ''
                })
            }
        }
    }
    else {
        foreach ($checkId in $mapA.Keys) {
            if (-not $mapB.ContainsKey($checkId)) {
                $row = $mapA[$checkId]
                $driftResults.Add([PSCustomObject]@{
                    CheckId        = $checkId
                    Setting        = $row.Setting
                    Category       = $row.Category
                    Section        = ''
                    ChangeType     = 'Removed'
                    PreviousStatus = $row.Status
                    CurrentStatus  = ''
                    PreviousValue  = $row.CurrentValue
                    CurrentValue   = ''
                })
            }
        }
    }

    # Build and write drift HTML
    $commonDir = Join-Path -Path $PSScriptRoot -ChildPath '..\Common'
    if (-not (Get-Command -Name Build-DriftHtml -ErrorAction SilentlyContinue)) {
        . (Join-Path -Path $commonDir -ChildPath 'Build-DriftHtml.ps1')
    }

    $driftHtmlFragment = Build-DriftHtml `
        -DriftReport @($driftResults) `
        -BaselineLabel $BaselineA `
        -BaselineTimestamp $timestampA

    if (-not $OutputPath) {
        $safeLabelB = $labelB -replace '[^\w\-]', '_'
        $OutputPath = Join-Path -Path $OutputFolder -ChildPath "_Drift-${safeA}-vs-${safeLabelB}.html"
    }

    # Wrap in a minimal standalone HTML page
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Drift: $BaselineA vs $labelB</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 20px; background: #f8fafc; color: #1e293b; }
  h1 { font-size: 1.4em; margin-bottom: 4px; }
  .meta { font-size: 0.85em; color: #64748b; margin-bottom: 20px; }
</style>
</head>
<body>
<h1>Policy Drift: $BaselineA &rarr; $labelB</h1>
<div class="meta">Tenant: $TenantId &nbsp;|&nbsp; $($driftResults.Count) changes detected</div>
$driftHtmlFragment
</body>
</html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    Write-Output "Drift report generated: $OutputPath ($($driftResults.Count) changes)"
}
