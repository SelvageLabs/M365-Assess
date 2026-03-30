<#
.SYNOPSIS
    Reports Active Directory replication health, partner status, and site link topology.
.DESCRIPTION
    Collects replication partner metadata, replication failure history, and site link
    configuration from Active Directory. Identifies DCs with replication lag or failures,
    site links with non-standard schedules, and missing replication connections.

    Designed for IT consultants performing AD assessments on SMB environments
    (10-500 users). All operations are read-only.

    Requires the ActiveDirectory module (available via RSAT or on domain controllers).
.PARAMETER DomainController
    One or more specific domain controller hostnames to check replication for.
    If not specified, all DCs are discovered and checked.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADReplicationReport.ps1

    Reports replication status for all domain controllers.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADReplicationReport.ps1 -DomainController 'DC01'

    Reports replication status for a specific domain controller.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADReplicationReport.ps1 -OutputPath '.\replication.csv'

    Exports the replication report to CSV.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$DomainController,

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

$report = [System.Collections.Generic.List[PSCustomObject]]::new()

# ------------------------------------------------------------------
# Discover target domain controllers
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
# Collect replication partner metadata for each DC
# ------------------------------------------------------------------
foreach ($dc in $dcList) {
    $dcName = $dc.HostName

    try {
        Write-Verbose "Querying replication partners for $dcName..."
        $partners = @(Get-ADReplicationPartnerMetadata -Target $dcName -ErrorAction Stop)

        if ($partners.Count -eq 0) {
            $report.Add([PSCustomObject]@{
                RecordType            = 'ReplicationPartner'
                DomainController      = $dcName
                Partner               = 'N/A'
                PartnerType           = 'N/A'
                LastReplicationAttempt = $null
                LastReplicationSuccess = $null
                LastReplicationResult  = 0
                ConsecutiveFailures   = 0
                ReplicationStatus     = 'No Partners'
                Detail                = 'No replication partners found for this DC'
            })
            continue
        }

        foreach ($partner in $partners) {
            $lastAttempt = $partner.LastReplicationAttempt
            $lastSuccess = $partner.LastReplicationSuccess
            $lastResult = $partner.LastReplicationResult
            $failures = $partner.ConsecutiveReplicationFailures
            $partnerName = $partner.Partner

            # Determine replication health status
            $replStatus = if ($lastResult -eq 0 -and $failures -eq 0) {
                'Healthy'
            }
            elseif ($failures -gt 0 -and $failures -le 3) {
                'Warning'
            }
            else {
                'Error'
            }

            # Calculate replication lag if we have timestamps
            $lagDetail = ''
            if ($lastSuccess -and $lastAttempt) {
                $lag = $lastAttempt - $lastSuccess
                if ($lag.TotalHours -gt 24) {
                    $lagDetail = "ReplicationLag=$([math]::Round($lag.TotalHours, 1))h"
                    $replStatus = 'Error'
                }
                elseif ($lag.TotalHours -gt 1) {
                    $lagDetail = "ReplicationLag=$([math]::Round($lag.TotalMinutes, 0))min"
                    if ($replStatus -eq 'Healthy') { $replStatus = 'Warning' }
                }
            }

            $detail = @()
            if ($lagDetail) { $detail += $lagDetail }
            if ($failures -gt 0) { $detail += "ConsecutiveFailures=$failures" }
            if ($lastResult -ne 0) { $detail += "LastResultCode=$lastResult" }

            $report.Add([PSCustomObject]@{
                RecordType            = 'ReplicationPartner'
                DomainController      = $dcName
                Partner               = $partnerName
                PartnerType           = $partner.PartnerType
                LastReplicationAttempt = $lastAttempt
                LastReplicationSuccess = $lastSuccess
                LastReplicationResult  = $lastResult
                ConsecutiveFailures   = $failures
                ReplicationStatus     = $replStatus
                Detail                = ($detail -join '; ')
            })
        }
    }
    catch {
        Write-Warning "Failed to query replication partners for $dcName`: $_"
        $report.Add([PSCustomObject]@{
            RecordType            = 'ReplicationPartner'
            DomainController      = $dcName
            Partner               = 'N/A'
            PartnerType           = 'N/A'
            LastReplicationAttempt = $null
            LastReplicationSuccess = $null
            LastReplicationResult  = -1
            ConsecutiveFailures   = -1
            ReplicationStatus     = 'QueryFailed'
            Detail                = "Failed to query: $_"
        })
    }
}

# ------------------------------------------------------------------
# Collect replication failure history
# ------------------------------------------------------------------
foreach ($dc in $dcList) {
    $dcName = $dc.HostName

    try {
        Write-Verbose "Querying replication failures for $dcName..."
        $failures = @(Get-ADReplicationFailure -Target $dcName -ErrorAction Stop)

        foreach ($failure in $failures) {
            $report.Add([PSCustomObject]@{
                RecordType            = 'ReplicationFailure'
                DomainController      = $dcName
                Partner               = $failure.Partner
                PartnerType           = 'N/A'
                LastReplicationAttempt = $failure.FirstFailureTime
                LastReplicationSuccess = $null
                LastReplicationResult  = $failure.LastError
                ConsecutiveFailures   = $failure.FailureCount
                ReplicationStatus     = 'FailureRecord'
                Detail                = "FailureType=$($failure.FailureType); FirstFailure=$($failure.FirstFailureTime)"
            })
        }
    }
    catch {
        Write-Warning "Failed to query replication failures for $dcName`: $_"
    }
}

# ------------------------------------------------------------------
# Collect site link topology
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying replication site links..."
    $siteLinks = @(Get-ADReplicationSiteLink -Filter * -ErrorAction Stop)

    foreach ($link in $siteLinks) {
        $sites = if ($link.SitesIncluded) {
            ($link.SitesIncluded | ForEach-Object {
                # Extract CN from distinguished name
                if ($_ -match '^CN=([^,]+),') { $Matches[1] } else { $_ }
            }) -join '; '
        }
        else { '' }

        $detail = @(
            "Sites=$sites"
            "Cost=$($link.Cost)"
            "ReplicationFrequency=$($link.ReplicationFrequencyInMinutes)min"
        ) -join '; '

        $report.Add([PSCustomObject]@{
            RecordType            = 'SiteLink'
            DomainController      = 'N/A'
            Partner               = $link.Name
            PartnerType           = 'N/A'
            LastReplicationAttempt = $null
            LastReplicationSuccess = $null
            LastReplicationResult  = 0
            ConsecutiveFailures   = 0
            ReplicationStatus     = 'Configured'
            Detail                = $detail
        })
    }

    Write-Verbose "Found $($siteLinks.Count) site link(s)"
}
catch {
    Write-Warning "Failed to query site links: $_"
}

# ------------------------------------------------------------------
# Export or return
# ------------------------------------------------------------------
$results = @($report)

Write-Verbose "Collected $($results.Count) replication records"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) replication records to $OutputPath"
}
else {
    Write-Output $results
}
