<#
.SYNOPSIS
    Reports domain controller inventory and health status via dcdiag.
.DESCRIPTION
    Discovers all domain controllers and collects OS version, site membership,
    FSMO roles, and Global Catalog status. Optionally runs dcdiag.exe to perform
    key diagnostic tests (Connectivity, Advertising, Services, SYSVOL, etc.)
    and parses the results into structured objects.

    If dcdiag.exe is not available (e.g. RSAT command-line tools not installed),
    DC inventory is still collected with dcdiag results marked as Skipped.

    Designed for IT consultants performing AD assessments on SMB environments
    (10-500 users). All operations are read-only.

    Requires the ActiveDirectory module (available via RSAT or on domain controllers).
.PARAMETER DomainController
    One or more specific domain controller hostnames to check. If not specified,
    all DCs are discovered via Get-ADDomainController.
.PARAMETER SkipDcdiag
    Skip dcdiag diagnostic tests. Only DC inventory information is collected.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADDCHealthReport.ps1

    Reports all DCs with dcdiag health status.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADDCHealthReport.ps1 -DomainController 'DC01','DC02'

    Checks only the specified domain controllers.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADDCHealthReport.ps1 -SkipDcdiag -OutputPath '.\dc-health.csv'

    Exports DC inventory without running dcdiag.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$DomainController,

    [Parameter()]
    [switch]$SkipDcdiag,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Verify ActiveDirectory module is available
# ------------------------------------------------------------------
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Error "The ActiveDirectory module is not installed. Install RSAT or run from a domain controller."
    return
}

Import-Module -Name ActiveDirectory -ErrorAction Stop

# ------------------------------------------------------------------
# Internal: invoke dcdiag.exe for a domain controller
# Defined conditionally so tests can inject a mock before running.
# ------------------------------------------------------------------
if (-not (Get-Command -Name 'Invoke-Dcdiag' -CommandType Function -ErrorAction SilentlyContinue)) {
function Invoke-Dcdiag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter()]
        [string[]]$Tests
    )

    $dcdiagExe = Get-Command -Name 'dcdiag.exe' -CommandType Application -ErrorAction SilentlyContinue
    if (-not $dcdiagExe) {
        throw "dcdiag.exe is not available on this machine. Install RSAT command-line tools or run from a domain controller."
    }

    $testArgs = @("/s:$Target")
    foreach ($test in $Tests) {
        $testArgs += "/test:$test"
    }

    $output = & dcdiag.exe @testArgs 2>&1
    return $output
}
} # end conditional Invoke-Dcdiag definition

# ------------------------------------------------------------------
# Define the dcdiag tests to run (SMB-appropriate subset)
# ------------------------------------------------------------------
$dcdiagTests = @(
    'Connectivity'
    'Advertising'
    'Services'
    'FrsEvent'
    'DFSREvent'
    'SysVolCheck'
    'KccEvent'
    'MachineAccount'
    'RidManager'
    'VerifyReferences'
)

# ------------------------------------------------------------------
# Discover domain controllers
# ------------------------------------------------------------------
try {
    Write-Verbose "Discovering domain controllers..."
    if ($DomainController) {
        $dcList = foreach ($dc in $DomainController) {
            try {
                Get-ADDomainController -Identity $dc
            }
            catch {
                Write-Warning "Could not find domain controller '$dc': $_"
            }
        }
        $dcList = @($dcList | Where-Object { $_ })
    }
    else {
        $dcList = @(Get-ADDomainController -Filter *)
    }

    if ($dcList.Count -eq 0) {
        Write-Error "No domain controllers found."
        return
    }

    Write-Verbose "Found $($dcList.Count) domain controller(s)"
}
catch {
    Write-Error "Failed to discover domain controllers: $_"
    return
}

# ------------------------------------------------------------------
# Collect DC info and run dcdiag
# ------------------------------------------------------------------
$report = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($dc in $dcList) {
    $dcName = $dc.HostName
    $fsmoRoles = if ($dc.OperationMasterRoles -and $dc.OperationMasterRoles.Count -gt 0) {
        ($dc.OperationMasterRoles -join ', ')
    }
    else { '' }

    if ($SkipDcdiag) {
        # Emit a single summary row with Skipped status
        $report.Add([PSCustomObject]@{
            DomainController = $dcName
            Site             = $dc.Site
            IPv4Address      = $dc.IPv4Address
            OperatingSystem  = $dc.OperatingSystem
            IsGlobalCatalog  = $dc.IsGlobalCatalog
            IsReadOnly       = $dc.IsReadOnly
            FSMORoles        = $fsmoRoles
            DcdiagTest       = 'N/A'
            DcdiagResult     = 'Skipped'
            DcdiagDetails    = 'dcdiag tests skipped via -SkipDcdiag parameter'
        })
        continue
    }

    # Run dcdiag
    try {
        Write-Verbose "Running dcdiag on $dcName..."
        $dcdiagOutput = Invoke-Dcdiag -Target $dcName -Tests $dcdiagTests

        # Parse dcdiag output
        $testPattern = '^\s*\.+\s+(\S+)\s+(passed|failed)\s+test\s+(.+)\s*$'
        $parsedTests = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($line in $dcdiagOutput) {
            $lineStr = if ($line -is [string]) { $line } else { $line.ToString() }

            if ($lineStr -match $testPattern) {
                $testResult = $Matches[2]
                $testName = $Matches[3].Trim()
                $details = ''

                if ($testResult -eq 'failed') {
                    $details = "Test $testName failed on $dcName"
                }

                $parsedTests.Add([PSCustomObject]@{
                    TestName = $testName
                    Result   = if ($testResult -eq 'passed') { 'Passed' } else { 'Failed' }
                    Details  = $details
                })
            }
        }

        if ($parsedTests.Count -gt 0) {
            foreach ($test in $parsedTests) {
                $report.Add([PSCustomObject]@{
                    DomainController = $dcName
                    Site             = $dc.Site
                    IPv4Address      = $dc.IPv4Address
                    OperatingSystem  = $dc.OperatingSystem
                    IsGlobalCatalog  = $dc.IsGlobalCatalog
                    IsReadOnly       = $dc.IsReadOnly
                    FSMORoles        = $fsmoRoles
                    DcdiagTest       = $test.TestName
                    DcdiagResult     = $test.Result
                    DcdiagDetails    = $test.Details
                })
            }
        }
        else {
            # dcdiag ran but no test results parsed (unexpected output format)
            $report.Add([PSCustomObject]@{
                DomainController = $dcName
                Site             = $dc.Site
                IPv4Address      = $dc.IPv4Address
                OperatingSystem  = $dc.OperatingSystem
                IsGlobalCatalog  = $dc.IsGlobalCatalog
                IsReadOnly       = $dc.IsReadOnly
                FSMORoles        = $fsmoRoles
                DcdiagTest       = 'N/A'
                DcdiagResult     = 'Unknown'
                DcdiagDetails    = 'dcdiag completed but no test results could be parsed from the output'
            })
        }
    }
    catch {
        # dcdiag failed entirely (e.g. dcdiag.exe not found)
        Write-Warning "dcdiag failed for $dcName`: $_"
        $report.Add([PSCustomObject]@{
            DomainController = $dcName
            Site             = $dc.Site
            IPv4Address      = $dc.IPv4Address
            OperatingSystem  = $dc.OperatingSystem
            IsGlobalCatalog  = $dc.IsGlobalCatalog
            IsReadOnly       = $dc.IsReadOnly
            FSMORoles        = $fsmoRoles
            DcdiagTest       = 'N/A'
            DcdiagResult     = 'Skipped'
            DcdiagDetails    = "dcdiag unavailable: $_"
        })
    }
}

# ------------------------------------------------------------------
# Export or return
# ------------------------------------------------------------------
$results = @($report)

Write-Verbose "Collected $($results.Count) DC health records"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) DC health records to $OutputPath"
}
else {
    Write-Output $results
}
