function Export-AssessmentBaseline {
    <#
    .SYNOPSIS
        Saves a named baseline snapshot of all security-config collector results.
    .DESCRIPTION
        Reads all security-config CSVs (those containing CheckId and Status columns)
        from the current assessment folder and serialises them to JSON in a labelled
        baseline directory under <OutputFolder>/Baselines/<Label>_<TenantId>/.
        A metadata file records the label, tenant, version, sections run, and
        timestamp so that Compare-AssessmentBaseline can validate compatibility.
    .PARAMETER AssessmentFolder
        Path to the completed assessment output folder.
    .PARAMETER OutputFolder
        Root output folder (parent of Baselines/). Typically the -OutputFolder
        value passed to Invoke-M365Assessment.
    .PARAMETER Label
        Human-readable baseline label (e.g. 'Q1-2026'). Used as the folder name
        prefix and referenced with -CompareBaseline on future runs.
    .PARAMETER TenantId
        Tenant identifier for the baseline folder name suffix.
    .PARAMETER Sections
        Array of section names that were assessed (recorded in metadata).
    .PARAMETER Version
        Assessment module version string (e.g. '1.15.0') recorded in metadata.
    .PARAMETER RegistryVersion
        Registry data version string (from controls/registry.json dataVersion)
        recorded in metadata to enable version-aware drift comparison.
    .EXAMPLE
        Export-AssessmentBaseline -AssessmentFolder $assessmentFolder `
            -OutputFolder '.\M365-Assessment' -Label 'Q1-2026' -TenantId 'contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AssessmentFolder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFolder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Label,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [string[]]$Sections = @(),

        [Parameter()]
        [string]$Version = '',

        [Parameter()]
        [string]$RegistryVersion = ''
    )

    # Sanitise label for use as a folder name
    $safeLabel  = $Label  -replace '[^\w\-]', '_'
    $safeTenant = $TenantId -replace '[^\w\.\-]', '_'
    $baselineDir = Join-Path -Path $OutputFolder -ChildPath "Baselines\${safeLabel}_${safeTenant}"

    if (-not (Test-Path -Path $baselineDir -PathType Container)) {
        $null = New-Item -Path $baselineDir -ItemType Directory -Force
    }

    # Copy each security-config CSV as JSON (identified by having CheckId + Status columns)
    $csvFiles = Get-ChildItem -Path $AssessmentFolder -Filter '*.csv' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_*' }

    $saved = 0
    $checkCount = 0
    foreach ($csvFile in $csvFiles) {
        try {
            $rows = Import-Csv -Path $csvFile.FullName -ErrorAction Stop
            if (-not $rows) { continue }
            $firstRow = $rows | Select-Object -First 1
            $props = $firstRow.PSObject.Properties.Name
            # Only baseline security-config tables (must have both CheckId and Status)
            if ('CheckId' -notin $props -or 'Status' -notin $props) { continue }

            $jsonName = [System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name) + '.json'
            $jsonPath = Join-Path -Path $baselineDir -ChildPath $jsonName
            $rows | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
            $checkCount += @($rows).Count
            $saved++
        }
        catch {
            Write-Warning "Baseline: skipped '$($csvFile.Name)': $_"
        }
    }

    # Write manifest after CSV scan (includes accurate CheckCount)
    $manifest = [PSCustomObject]@{
        Label             = $Label
        SavedAt           = (Get-Date -Format 'o')
        TenantId          = $TenantId
        AssessmentVersion = $Version
        RegistryVersion   = $RegistryVersion
        CheckCount        = $checkCount
        Sections          = $Sections
    }
    $manifestPath = Join-Path -Path $baselineDir -ChildPath 'manifest.json'
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

    Write-Verbose "Baseline '$Label' saved to '$baselineDir' ($saved collector files, $checkCount checks)"
    return $baselineDir
}
