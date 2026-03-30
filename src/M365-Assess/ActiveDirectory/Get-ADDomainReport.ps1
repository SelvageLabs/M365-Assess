<#
.SYNOPSIS
    Reports Active Directory domain and forest topology information.
.DESCRIPTION
    Collects domain, forest, site, and trust relationship details from Active
    Directory. Provides FSMO role holder locations, functional levels, site/subnet
    topology, and trust configurations.

    Designed for IT consultants performing AD assessments on SMB environments
    (10-500 users). All operations are read-only.

    Requires the ActiveDirectory module (available via RSAT or on domain controllers).
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADDomainReport.ps1

    Returns domain, forest, site, and trust information as PSCustomObjects.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADDomainReport.ps1 -OutputPath '.\ad-domain-report.csv'

    Exports the domain topology report to CSV.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service Graph -Scopes 'Organization.Read.All'
    PS> .\ActiveDirectory\Get-ADDomainReport.ps1

    Can be combined with Graph-connected scripts for a hybrid assessment.
#>
[CmdletBinding()]
param(
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
# Domain information
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying domain information..."
    $domain = Get-ADDomain

    $report.Add([PSCustomObject]@{
        RecordType           = 'Domain'
        Name                 = $domain.DNSRoot
        DistinguishedName    = $domain.DistinguishedName
        NetBIOSName          = $domain.NetBIOSName
        FunctionalLevel      = $domain.DomainMode
        PDCEmulator          = $domain.PDCEmulator
        RIDMaster            = $domain.RIDMaster
        InfrastructureMaster = $domain.InfrastructureMaster
        Detail               = ''
    })

    Write-Verbose "Domain: $($domain.DNSRoot) ($($domain.DomainMode))"
}
catch {
    Write-Error "Failed to query AD domain: $_"
    return
}

# ------------------------------------------------------------------
# Forest information
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying forest information..."
    $forest = Get-ADForest

    $globalCatalogs = if ($forest.GlobalCatalogs) {
        ($forest.GlobalCatalogs -join '; ')
    }
    else { '' }

    $sites = if ($forest.Sites) {
        ($forest.Sites -join '; ')
    }
    else { '' }

    $domains = if ($forest.Domains) {
        ($forest.Domains -join '; ')
    }
    else { '' }

    $detail = @(
        "SchemaMaster=$($forest.SchemaMaster)"
        "DomainNamingMaster=$($forest.DomainNamingMaster)"
        "GlobalCatalogs=$globalCatalogs"
        "Domains=$domains"
        "Sites=$sites"
    ) -join '; '

    $report.Add([PSCustomObject]@{
        RecordType           = 'Forest'
        Name                 = $forest.Name
        DistinguishedName    = $forest.RootDomain
        NetBIOSName          = ''
        FunctionalLevel      = $forest.ForestMode
        PDCEmulator          = ''
        RIDMaster            = ''
        InfrastructureMaster = ''
        Detail               = $detail
    })

    Write-Verbose "Forest: $($forest.Name) ($($forest.ForestMode))"
}
catch {
    Write-Warning "Failed to query AD forest: $_"
}

# ------------------------------------------------------------------
# Site information
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying AD sites..."
    $adSites = Get-ADReplicationSite -Filter *

    foreach ($site in $adSites) {
        $subnets = try {
            $siteSubnets = Get-ADReplicationSubnet -Filter "Site -eq '$($site.DistinguishedName)'" -ErrorAction SilentlyContinue
            if ($siteSubnets) {
                ($siteSubnets | ForEach-Object { $_.Name }) -join '; '
            }
            else { '' }
        }
        catch { '' }

        $report.Add([PSCustomObject]@{
            RecordType           = 'Site'
            Name                 = $site.Name
            DistinguishedName    = $site.DistinguishedName
            NetBIOSName          = ''
            FunctionalLevel      = ''
            PDCEmulator          = ''
            RIDMaster            = ''
            InfrastructureMaster = ''
            Detail               = if ($subnets) { "Subnets=$subnets" } else { 'Subnets=None' }
        })
    }

    Write-Verbose "Found $(@($adSites).Count) AD site(s)"
}
catch {
    Write-Warning "Failed to query AD sites: $_"
}

# ------------------------------------------------------------------
# Trust relationships
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying trust relationships..."
    $trusts = Get-ADTrust -Filter *

    if ($trusts) {
        foreach ($trust in $trusts) {
            $direction = switch ($trust.Direction) {
                0 { 'Disabled' }
                1 { 'Inbound' }
                2 { 'Outbound' }
                3 { 'Bidirectional' }
                default { $trust.Direction }
            }

            $trustType = switch ($trust.TrustType) {
                1 { 'Downlevel (Windows NT)' }
                2 { 'Uplevel (Windows 2000+)' }
                3 { 'MIT (Kerberos)' }
                4 { 'DCE' }
                default { $trust.TrustType }
            }

            $detail = @(
                "Direction=$direction"
                "TrustType=$trustType"
                "SelectiveAuth=$($trust.SelectiveAuthentication)"
                "ForestTransitive=$($trust.ForestTransitive)"
            ) -join '; '

            $report.Add([PSCustomObject]@{
                RecordType           = 'Trust'
                Name                 = $trust.Name
                DistinguishedName    = $trust.DistinguishedName
                NetBIOSName          = ''
                FunctionalLevel      = ''
                PDCEmulator          = ''
                RIDMaster            = ''
                InfrastructureMaster = ''
                Detail               = $detail
            })
        }
        Write-Verbose "Found $(@($trusts).Count) trust relationship(s)"
    }
    else {
        Write-Verbose "No trust relationships found"
    }
}
catch {
    Write-Warning "Failed to query AD trusts: $_"
}

# ------------------------------------------------------------------
# Export or return
# ------------------------------------------------------------------
$results = @($report)

Write-Verbose "Collected $($results.Count) AD domain topology records"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) AD domain topology records to $OutputPath"
}
else {
    Write-Output $results
}
