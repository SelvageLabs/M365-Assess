<#
.SYNOPSIS
    Reports on accepted domains, inbound/outbound connectors, and transport rules in Exchange Online.
.DESCRIPTION
    Collects mail flow configuration details including accepted domains, inbound connectors,
    outbound connectors, and transport rules. Consolidates key properties into a single
    report for M365 security assessments, migration planning, and mail routing reviews.

    Requires ExchangeOnlineManagement module and an active Exchange Online connection.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service ExchangeOnline
    PS> .\Exchange-Online\Get-MailFlowReport.ps1

    Displays all accepted domains, connectors, and transport rules.
.EXAMPLE
    PS> .\Exchange-Online\Get-MailFlowReport.ps1 -OutputPath '.\mail-flow-report.csv'

    Exports the full mail flow configuration report to CSV.
.EXAMPLE
    PS> .\Exchange-Online\Get-MailFlowReport.ps1 -Verbose

    Displays the mail flow report with detailed progress messages for each item type.
#>
[CmdletBinding()]
param(
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

# Accepted Domains
Write-Verbose "Retrieving accepted domains..."
try {
    $acceptedDomains = @(Get-AcceptedDomain)
    Write-Verbose "Found $($acceptedDomains.Count) accepted domains"

    foreach ($domain in $acceptedDomains) {
        $details = @(
            "DomainType=$($domain.DomainType)"
            "Default=$($domain.Default)"
        )

        $results.Add([PSCustomObject]@{
            ItemType = 'Domain'
            Name     = $domain.DomainName
            Status   = if ($domain.Default) { 'Default' } else { 'Active' }
            Details  = $details -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve accepted domains: $_"
}

# Inbound Connectors
Write-Verbose "Retrieving inbound connectors..."
try {
    $inboundConnectors = @(Get-InboundConnector)
    Write-Verbose "Found $($inboundConnectors.Count) inbound connectors"

    foreach ($connector in $inboundConnectors) {
        $details = @(
            "ConnectorType=$($connector.ConnectorType)"
            "SenderDomains=$($connector.SenderDomains -join ', ')"
            "RequireTls=$($connector.RequireTls)"
            "RestrictDomainsToCertificate=$($connector.RestrictDomainsToCertificate)"
        )

        if ($connector.SenderIPAddresses.Count -gt 0) {
            $details += "SenderIPAddresses=$($connector.SenderIPAddresses -join ', ')"
        }

        if ($connector.TlsSenderCertificateName) {
            $details += "TlsSenderCertificateName=$($connector.TlsSenderCertificateName)"
        }

        $results.Add([PSCustomObject]@{
            ItemType = 'InboundConnector'
            Name     = $connector.Name
            Status   = if ($connector.Enabled) { 'Enabled' } else { 'Disabled' }
            Details  = $details -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve inbound connectors: $_"
}

# Outbound Connectors
Write-Verbose "Retrieving outbound connectors..."
try {
    $outboundConnectors = @(Get-OutboundConnector)
    Write-Verbose "Found $($outboundConnectors.Count) outbound connectors"

    foreach ($connector in $outboundConnectors) {
        $details = @(
            "ConnectorType=$($connector.ConnectorType)"
            "RecipientDomains=$($connector.RecipientDomains -join ', ')"
            "UseMXRecord=$($connector.UseMXRecord)"
            "TlsSettings=$($connector.TlsSettings)"
        )

        if ($connector.SmartHosts.Count -gt 0) {
            $details += "SmartHosts=$($connector.SmartHosts -join ', ')"
        }

        $results.Add([PSCustomObject]@{
            ItemType = 'OutboundConnector'
            Name     = $connector.Name
            Status   = if ($connector.Enabled) { 'Enabled' } else { 'Disabled' }
            Details  = $details -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve outbound connectors: $_"
}

# Transport Rules
Write-Verbose "Retrieving transport rules..."
try {
    $transportRules = @(Get-TransportRule)
    Write-Verbose "Found $($transportRules.Count) transport rules"

    foreach ($rule in $transportRules) {
        $details = @(
            "Priority=$($rule.Priority)"
            "Mode=$($rule.Mode)"
        )

        if ($rule.SentTo) {
            $details += "SentTo=$($rule.SentTo -join ', ')"
        }
        if ($rule.SentToMemberOf) {
            $details += "SentToMemberOf=$($rule.SentToMemberOf -join ', ')"
        }
        if ($rule.FromMemberOf) {
            $details += "FromMemberOf=$($rule.FromMemberOf -join ', ')"
        }
        if ($rule.From) {
            $details += "From=$($rule.From -join ', ')"
        }
        if ($rule.SubjectContainsWords) {
            $details += "SubjectContains=$($rule.SubjectContainsWords -join ', ')"
        }
        if ($rule.HasAttachment) {
            $details += "HasAttachment=$($rule.HasAttachment)"
        }

        # Capture the actions applied by this rule
        $actionParts = @()
        if ($rule.AddToRecipients) {
            $actionParts += "AddToRecipients"
        }
        if ($rule.BlindCopyTo) {
            $actionParts += "BlindCopyTo"
        }
        if ($rule.ModerateMessageByUser) {
            $actionParts += "ModerateMessageByUser"
        }
        if ($rule.RejectMessageReasonText) {
            $actionParts += "RejectMessage"
        }
        if ($rule.DeleteMessage) {
            $actionParts += "DeleteMessage"
        }
        if ($rule.PrependSubject) {
            $actionParts += "PrependSubject=$($rule.PrependSubject)"
        }
        if ($rule.SetHeaderName) {
            $actionParts += "SetHeader=$($rule.SetHeaderName):$($rule.SetHeaderValue)"
        }
        if ($rule.ApplyHtmlDisclaimerText) {
            $actionParts += "ApplyDisclaimer"
        }

        if ($actionParts.Count -gt 0) {
            $details += "Actions=$($actionParts -join ', ')"
        }

        $results.Add([PSCustomObject]@{
            ItemType = 'TransportRule'
            Name     = $rule.Name
            Status   = if ($rule.State -eq 'Enabled') { 'Enabled' } else { 'Disabled' }
            Details  = $details -join '; '
        })
    }
}
catch {
    Write-Warning "Failed to retrieve transport rules: $_"
}

Write-Verbose "Mail flow report complete: $($results.Count) total items"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported mail flow report ($($results.Count) items) to $OutputPath"
}
else {
    Write-Output $results
}
