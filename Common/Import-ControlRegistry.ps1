<#
.SYNOPSIS
    Loads the control registry and builds lookup tables for the report layer.
.DESCRIPTION
    Reads controls/registry.json and returns a hashtable keyed by CheckId.
    Also builds a reverse lookup from CIS control IDs to CheckIds (stored
    under the special key '__cisReverseLookup') for backward compatibility
    with CSVs that still use the CisControl column.
.PARAMETER ControlsPath
    Path to the controls/ directory containing registry.json.
.OUTPUTS
    [hashtable] - Keys are CheckIds, values are registry entry objects.
    Special key '__cisReverseLookup' maps CIS control IDs to CheckIds.
#>
function Import-ControlRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ControlsPath
    )

    $registryPath = Join-Path -Path $ControlsPath -ChildPath 'registry.json'
    if (-not (Test-Path -Path $registryPath)) {
        Write-Warning "Control registry not found: $registryPath"
        return @{}
    }

    $raw = Get-Content -Path $registryPath -Raw | ConvertFrom-Json
    $lookup = @{}
    $cisReverse = @{}

    foreach ($check in $raw.checks) {
        $entry = @{
            checkId           = $check.checkId
            name              = $check.name
            category          = $check.category
            collector         = $check.collector
            hasAutomatedCheck = $check.hasAutomatedCheck
            licensing         = $check.licensing
            frameworks        = @{}
        }

        # Convert framework PSCustomObject properties to hashtable
        foreach ($prop in $check.frameworks.PSObject.Properties) {
            $entry.frameworks[$prop.Name] = $prop.Value
        }

        $lookup[$check.checkId] = $entry

        # Build CIS reverse lookup
        $cisMapping = $check.frameworks.'cis-m365-v6'
        if ($cisMapping -and $cisMapping.controlId) {
            $cisReverse[$cisMapping.controlId] = $check.checkId
        }
    }

    $lookup['__cisReverseLookup'] = $cisReverse
    return $lookup
}
