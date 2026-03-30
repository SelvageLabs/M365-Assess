<#
.SYNOPSIS
    Finds Active Directory computer accounts that have not authenticated recently.
.DESCRIPTION
    Queries Active Directory for computer accounts whose last logon timestamp
    exceeds the specified inactivity threshold. Useful for identifying stale
    machine accounts during security reviews, AD cleanups, and compliance audits.

    Requires the ActiveDirectory module (available via RSAT or on domain controllers).
.PARAMETER DaysInactive
    Number of days since last logon to consider a computer stale. Defaults to 90.
.PARAMETER SearchBase
    Optional distinguished name of the OU to search. If not specified, searches
    the entire domain.
.PARAMETER IncludeDisabled
    Include disabled computer accounts in the results. By default only enabled
    accounts are returned.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> .\ActiveDirectory\Get-StaleComputers.ps1 -DaysInactive 90

    Lists all enabled computer accounts that have not logged on in 90+ days.
.EXAMPLE
    PS> .\ActiveDirectory\Get-StaleComputers.ps1 -DaysInactive 60 -SearchBase 'OU=Workstations,DC=contoso,DC=com'

    Searches only the Workstations OU for computers inactive for 60+ days.
.EXAMPLE
    PS> .\ActiveDirectory\Get-StaleComputers.ps1 -DaysInactive 30 -IncludeDisabled -OutputPath '.\stale-computers.csv'

    Exports all stale computers (including disabled) to CSV.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$DaysInactive = 90,

    [Parameter()]
    [string]$SearchBase,

    [Parameter()]
    [switch]$IncludeDisabled,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify ActiveDirectory module is available
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Error "The ActiveDirectory module is not installed. Install RSAT or run from a domain controller."
    return
}

Import-Module -Name ActiveDirectory -ErrorAction Stop

$cutoffDate = (Get-Date).AddDays(-$DaysInactive)

Write-Verbose "Searching for computers inactive since $($cutoffDate.ToString('yyyy-MM-dd'))"

$adParams = @{
    Filter     = "LastLogonTimestamp -lt '$($cutoffDate.ToFileTime())' -or LastLogonTimestamp -notlike '*'"
    Properties = @('LastLogonTimestamp', 'OperatingSystem', 'OperatingSystemVersion', 'Description', 'Enabled', 'WhenCreated', 'DistinguishedName')
}

if ($SearchBase) {
    $adParams['SearchBase'] = $SearchBase
    Write-Verbose "Scoped to: $SearchBase"
}

try {
    $computers = Get-ADComputer @adParams
}
catch {
    Write-Error "Failed to query Active Directory: $_"
    return
}

# Filter by enabled status unless IncludeDisabled is set
if (-not $IncludeDisabled) {
    $computers = $computers | Where-Object { $_.Enabled -eq $true }
}

$results = foreach ($computer in $computers) {
    $lastLogon = if ($computer.LastLogonTimestamp) {
        [DateTime]::FromFileTime($computer.LastLogonTimestamp)
    }
    else {
        $null
    }

    $daysSince = if ($lastLogon) {
        [math]::Round(((Get-Date) - $lastLogon).TotalDays)
    }
    else {
        'Never'
    }

    [PSCustomObject]@{
        Name                   = $computer.Name
        Enabled                = $computer.Enabled
        OperatingSystem        = $computer.OperatingSystem
        OperatingSystemVersion = $computer.OperatingSystemVersion
        LastLogon              = $lastLogon
        DaysSinceLogon         = $daysSince
        Description            = $computer.Description
        WhenCreated            = $computer.WhenCreated
        DistinguishedName      = $computer.DistinguishedName
    }
}

$results = @($results) | Sort-Object -Property DaysSinceLogon -Descending

Write-Verbose "Found $($results.Count) stale computer accounts"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) stale computers to $OutputPath"
}
else {
    Write-Output $results
}
