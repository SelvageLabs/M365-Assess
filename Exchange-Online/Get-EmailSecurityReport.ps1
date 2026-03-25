<#
.SYNOPSIS
    Reports on email security policies and DNS authentication configuration in Exchange Online.
.DESCRIPTION
    Collects anti-spam (hosted content filter), anti-phish, anti-malware, and DKIM signing
    configurations. Optionally checks SPF and DMARC DNS records for accepted domains.
    Provides a consolidated view for M365 security assessments and compliance reviews.

    Requires ExchangeOnlineManagement module and an active Exchange Online connection.
    DNS checks use Resolve-DnsRecord (cross-platform: Resolve-DnsName on Windows, dig on macOS/Linux).
.PARAMETER IncludeDnsChecks
    When specified, performs SPF and DMARC DNS lookups for each accepted domain in the tenant.
    Requires Resolve-DnsName (Windows) or dig (macOS/Linux). Failures are handled gracefully.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service ExchangeOnline
    PS> .\Exchange-Online\Get-EmailSecurityReport.ps1

    Displays all email security policies (anti-spam, anti-phish, anti-malware, DKIM).
.EXAMPLE
    PS> .\Exchange-Online\Get-EmailSecurityReport.ps1 -IncludeDnsChecks -OutputPath '.\email-security.csv'

    Exports email security policies along with SPF/DMARC DNS checks to CSV.
.EXAMPLE
    PS> .\Exchange-Online\Get-EmailSecurityReport.ps1 -IncludeDnsChecks -Verbose

    Displays email security report with DNS authentication checks and detailed progress.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludeDnsChecks,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify EXO connection
try {
    $null = Get-OrganizationConfig -ErrorAction Stop
}
catch {
    Write-Error "Not connected to Exchange Online. Run Connect-Service -Service ExchangeOnline first."
    return
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Anti-Spam Policies (Hosted Content Filter)
Write-Verbose "Retrieving anti-spam policies..."
try {
    $antiSpamPolicies = @(Get-HostedContentFilterPolicy)
    Write-Verbose "Found $($antiSpamPolicies.Count) anti-spam policies"

    foreach ($policy in $antiSpamPolicies) {
        $keySettings = @(
            "BulkThreshold=$($policy.BulkThreshold)"
            "SpamAction=$($policy.SpamAction)"
            "HighConfidenceSpamAction=$($policy.HighConfidenceSpamAction)"
            "PhishSpamAction=$($policy.PhishSpamAction)"
            "BulkSpamAction=$($policy.BulkSpamAction)"
            "QuarantineRetentionPeriod=$($policy.QuarantineRetentionPeriod)"
            "InlineSafetyTipsEnabled=$($policy.InlineSafetyTipsEnabled)"
            "SpamZapEnabled=$($policy.SpamZapEnabled)"
            "PhishZapEnabled=$($policy.PhishZapEnabled)"
        )

        if ($policy.AllowedSenders.Count -gt 0 -or $policy.AllowedSenderDomains.Count -gt 0) {
            $keySettings += "AllowedSenderDomains=$($policy.AllowedSenderDomains.Count)"
            $keySettings += "AllowedSenders=$($policy.AllowedSenders.Count)"
        }

        if ($policy.BlockedSenders.Count -gt 0 -or $policy.BlockedSenderDomains.Count -gt 0) {
            $keySettings += "BlockedSenderDomains=$($policy.BlockedSenderDomains.Count)"
            $keySettings += "BlockedSenders=$($policy.BlockedSenders.Count)"
        }

        $results.Add([PSCustomObject]@{
            PolicyType  = 'AntiSpam'
            Name        = $policy.Name
            Enabled     = $policy.IsDefault -or ($null -ne $policy.IsEnabled -and $policy.IsEnabled)
            KeySettings = $keySettings -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve anti-spam policies: $_"
}

# Anti-Phish Policies
Write-Verbose "Retrieving anti-phish policies..."
try {
    $antiPhishPolicies = @(Get-AntiPhishPolicy)
    Write-Verbose "Found $($antiPhishPolicies.Count) anti-phish policies"

    foreach ($policy in $antiPhishPolicies) {
        $keySettings = @(
            "Enabled=$($policy.Enabled)"
            "PhishThresholdLevel=$($policy.PhishThresholdLevel)"
            "EnableMailboxIntelligence=$($policy.EnableMailboxIntelligence)"
            "EnableMailboxIntelligenceProtection=$($policy.EnableMailboxIntelligenceProtection)"
            "EnableSpoofIntelligence=$($policy.EnableSpoofIntelligence)"
            "EnableFirstContactSafetyTips=$($policy.EnableFirstContactSafetyTips)"
            "EnableUnauthenticatedSender=$($policy.EnableUnauthenticatedSender)"
            "EnableViaTag=$($policy.EnableViaTag)"
        )

        if ($policy.EnableTargetedUserProtection) {
            $keySettings += "TargetedUserProtection=Enabled"
            $keySettings += "TargetedUsersToProtectCount=$($policy.TargetedUsersToProtect.Count)"
        }
        if ($policy.EnableTargetedDomainsProtection) {
            $keySettings += "TargetedDomainsProtection=Enabled"
        }
        if ($policy.EnableOrganizationDomainsProtection) {
            $keySettings += "OrganizationDomainsProtection=Enabled"
        }

        $results.Add([PSCustomObject]@{
            PolicyType  = 'AntiPhish'
            Name        = $policy.Name
            Enabled     = $policy.Enabled
            KeySettings = $keySettings -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve anti-phish policies: $_"
}

# Anti-Malware Policies
Write-Verbose "Retrieving anti-malware policies..."
try {
    $malwarePolicies = @(Get-MalwareFilterPolicy)
    Write-Verbose "Found $($malwarePolicies.Count) anti-malware policies"

    foreach ($policy in $malwarePolicies) {
        $keySettings = @(
            "EnableFileFilter=$($policy.EnableFileFilter)"
            "FileFilterAction=$($policy.FileFilterAction)"
            "ZapEnabled=$($policy.ZapEnabled)"
            "EnableInternalSenderAdminNotifications=$($policy.EnableInternalSenderAdminNotifications)"
            "EnableExternalSenderAdminNotifications=$($policy.EnableExternalSenderAdminNotifications)"
        )

        if ($policy.FileTypes.Count -gt 0) {
            $keySettings += "FileTypesCount=$($policy.FileTypes.Count)"
        }

        if ($policy.EnableInternalSenderAdminNotifications -or $policy.EnableExternalSenderAdminNotifications) {
            if ($policy.InternalSenderAdminAddress) {
                $keySettings += "InternalAdminNotify=$($policy.InternalSenderAdminAddress)"
            }
            if ($policy.ExternalSenderAdminAddress) {
                $keySettings += "ExternalAdminNotify=$($policy.ExternalSenderAdminAddress)"
            }
        }

        $results.Add([PSCustomObject]@{
            PolicyType  = 'AntiMalware'
            Name        = $policy.Name
            Enabled     = $policy.IsDefault -or ($null -ne $policy.IsEnabled -and $policy.IsEnabled)
            KeySettings = $keySettings -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve anti-malware policies: $_"
}

# DKIM Signing Configuration
Write-Verbose "Retrieving DKIM signing configuration..."
try {
    $dkimConfigs = @(Get-DkimSigningConfig)
    Write-Verbose "Found $($dkimConfigs.Count) DKIM configurations"

    foreach ($config in $dkimConfigs) {
        $keySettings = @(
            "Domain=$($config.Domain)"
            "Enabled=$($config.Enabled)"
            "Status=$($config.Status)"
        )

        if ($config.Selector1CNAME) {
            $keySettings += "Selector1CNAME=$($config.Selector1CNAME)"
        }
        if ($config.Selector2CNAME) {
            $keySettings += "Selector2CNAME=$($config.Selector2CNAME)"
        }

        $results.Add([PSCustomObject]@{
            PolicyType  = 'DKIM'
            Name        = $config.Domain
            Enabled     = $config.Enabled
            KeySettings = $keySettings -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve DKIM signing configuration: $_"
}

# DNS Authentication Checks (SPF and DMARC)
if ($IncludeDnsChecks) {
    Write-Verbose "Performing DNS authentication checks (SPF/DMARC)..."

    # Load cross-platform DNS resolver (Resolve-DnsName on Windows, dig on macOS/Linux)
    $dnsHelperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Common\Resolve-DnsRecord.ps1'
    $dnsCommandAvailable = $false
    if (Test-Path -Path $dnsHelperPath) {
        . $dnsHelperPath
        $dnsCommandAvailable = $null -ne (Get-Command -Name Resolve-DnsRecord -ErrorAction SilentlyContinue)
    }
    if (-not $dnsCommandAvailable) {
        Write-Warning "Resolve-DnsRecord helper is not available. Skipping DNS checks."
    }

    if ($dnsCommandAvailable) {
        # Retrieve accepted domains for DNS checks
        $domainsForDns = @()
        try {
            $domainsForDns = @(Get-AcceptedDomain)
            Write-Verbose "Checking DNS records for $($domainsForDns.Count) accepted domains"
        }
        catch {
            Write-Warning "Failed to retrieve accepted domains for DNS checks: $_"
        }

        foreach ($domain in $domainsForDns) {
            $domainName = $domain.DomainName

            # SPF check
            $spfRecord = $null
            try {
                $txtRecords = @(Resolve-DnsRecord -Name $domainName -Type TXT -ErrorAction Stop)
                $spfRecord = ($txtRecords | Where-Object {
                    $_.Strings -and ($_.Strings -join '' -match '^v=spf1')
                } | Select-Object -First 1)
            }
            catch {
                Write-Verbose "DNS lookup failed for SPF on $domainName`: $_"
            }

            $spfValue = if ($spfRecord) {
                $spfRecord.Strings -join ''
            }
            else {
                'Not Found'
            }

            $spfKeySettings = @(
                "Domain=$domainName"
                "Record=$spfValue"
            )

            # Evaluate SPF configuration quality
            if ($spfValue -ne 'Not Found') {
                if ($spfValue -match '-all$') {
                    $spfKeySettings += "Enforcement=HardFail (-all)"
                }
                elseif ($spfValue -match '~all$') {
                    $spfKeySettings += "Enforcement=SoftFail (~all)"
                }
                elseif ($spfValue -match '\?all$') {
                    $spfKeySettings += "Enforcement=Neutral (?all)"
                }
                elseif ($spfValue -match '\+all$') {
                    $spfKeySettings += "Enforcement=Pass (+all) WARNING"
                }
            }

            $results.Add([PSCustomObject]@{
                PolicyType  = 'SPF'
                Name        = $domainName
                Enabled     = ($spfValue -ne 'Not Found')
                KeySettings = $spfKeySettings -join '; '
            })

            # DMARC check
            $dmarcRecord = $null
            try {
                $dmarcTxtRecords = @(Resolve-DnsRecord -Name "_dmarc.$domainName" -Type TXT -ErrorAction Stop)
                $dmarcRecord = ($dmarcTxtRecords | Where-Object {
                    $_.Strings -and ($_.Strings -join '' -match '^v=DMARC1')
                } | Select-Object -First 1)
            }
            catch {
                Write-Verbose "DNS lookup failed for DMARC on $domainName`: $_"
            }

            $dmarcValue = if ($dmarcRecord) {
                $dmarcRecord.Strings -join ''
            }
            else {
                'Not Found'
            }

            $dmarcKeySettings = @(
                "Domain=$domainName"
                "Record=$dmarcValue"
            )

            # Parse DMARC policy
            if ($dmarcValue -ne 'Not Found') {
                if ($dmarcValue -match 'p=(\w+)') {
                    $dmarcKeySettings += "Policy=$($Matches[1])"
                }
                if ($dmarcValue -match 'sp=(\w+)') {
                    $dmarcKeySettings += "SubdomainPolicy=$($Matches[1])"
                }
                if ($dmarcValue -match 'pct=(\d+)') {
                    $dmarcKeySettings += "Percentage=$($Matches[1])%"
                }
                if ($dmarcValue -match 'rua=([^;]+)') {
                    $dmarcKeySettings += "AggregateReport=$($Matches[1])"
                }
                if ($dmarcValue -match 'ruf=([^;]+)') {
                    $dmarcKeySettings += "ForensicReport=$($Matches[1])"
                }
            }

            $results.Add([PSCustomObject]@{
                PolicyType  = 'DMARC'
                Name        = $domainName
                Enabled     = ($dmarcValue -ne 'Not Found')
                KeySettings = $dmarcKeySettings -join '; '
            })
        }
    }
}

Write-Verbose "Email security report complete: $($results.Count) total entries"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported email security report ($($results.Count) entries) to $OutputPath"
}
else {
    Write-Output $results
}
