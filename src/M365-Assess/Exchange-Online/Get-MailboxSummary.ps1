<#
.SYNOPSIS
    Generates a summary of mailbox types, distribution groups, and M365 groups in Exchange Online.
.DESCRIPTION
    Counts mailboxes by type (User, Shared, Room, Equipment), distribution groups, and
    Microsoft 365 (Unified) groups across the tenant. Provides a high-level inventory
    useful for M365 assessments, migration planning, and tenant health reviews.

    Requires ExchangeOnlineManagement module and an active Exchange Online connection.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service ExchangeOnline
    PS> .\Exchange-Online\Get-MailboxSummary.ps1

    Displays a summary of all mailbox types, distribution groups, and M365 groups.
.EXAMPLE
    PS> .\Exchange-Online\Get-MailboxSummary.ps1 -OutputPath '.\mailbox-summary.csv'

    Exports the mailbox summary to a CSV file for client reporting.
.EXAMPLE
    PS> .\Exchange-Online\Get-MailboxSummary.ps1 -Verbose

    Displays a mailbox summary with detailed progress messages.
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

# Retrieve all mailboxes
Write-Verbose "Retrieving all mailboxes (this may take a moment in large tenants)..."
try {
    $allMailboxes = @(Get-EXOMailbox -ResultSize Unlimited -Properties RecipientTypeDetails)
}
catch {
    Write-Error "Failed to retrieve mailboxes: $_"
    return
}

# Count mailboxes by type
$userMailboxes = @($allMailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' })
$sharedMailboxes = @($allMailboxes | Where-Object { $_.RecipientTypeDetails -eq 'SharedMailbox' })
$roomMailboxes = @($allMailboxes | Where-Object { $_.RecipientTypeDetails -eq 'RoomMailbox' })
$equipmentMailboxes = @($allMailboxes | Where-Object { $_.RecipientTypeDetails -eq 'EquipmentMailbox' })

Write-Verbose "Found $($allMailboxes.Count) total mailboxes: $($userMailboxes.Count) User, $($sharedMailboxes.Count) Shared, $($roomMailboxes.Count) Room, $($equipmentMailboxes.Count) Equipment"

# Retrieve distribution groups
Write-Verbose "Retrieving distribution groups..."
try {
    $distributionGroups = @(Get-DistributionGroup -ResultSize Unlimited)
}
catch {
    Write-Warning "Failed to retrieve distribution groups: $_"
    $distributionGroups = @()
}

# Retrieve Microsoft 365 groups
Write-Verbose "Retrieving Microsoft 365 groups..."
try {
    $m365Groups = @(Get-UnifiedGroup -ResultSize Unlimited)
}
catch {
    Write-Warning "Failed to retrieve Microsoft 365 groups: $_"
    $m365Groups = @()
}

# Calculate total items via mailbox statistics
$totalItemsDisplay = 'N/A'
try {
    Write-Verbose "Retrieving mailbox statistics for item counts..."
    $totalItemCount = 0
    $statsAvailable = $true
    foreach ($mbx in $allMailboxes) {
        try {
            $stats = Get-EXOMailboxStatistics -Identity $mbx.ExchangeObjectId -ErrorAction Stop
            if ($null -ne $stats.ItemCount) {
                $totalItemCount += $stats.ItemCount
            }
        }
        catch {
            $statsAvailable = $false
        }
    }
    if ($statsAvailable -and $allMailboxes.Count -gt 0) {
        $totalItemsDisplay = $totalItemCount.ToString()
    }
}
catch {
    Write-Warning "Failed to retrieve mailbox statistics: $_"
}

# Build summary output
$results = @(
    [PSCustomObject]@{
        Metric = 'TotalMailboxes'
        Count  = $allMailboxes.Count
    }
    [PSCustomObject]@{
        Metric = 'UserMailboxes'
        Count  = $userMailboxes.Count
    }
    [PSCustomObject]@{
        Metric = 'SharedMailboxes'
        Count  = $sharedMailboxes.Count
    }
    [PSCustomObject]@{
        Metric = 'RoomMailboxes'
        Count  = $roomMailboxes.Count
    }
    [PSCustomObject]@{
        Metric = 'EquipmentMailboxes'
        Count  = $equipmentMailboxes.Count
    }
    [PSCustomObject]@{
        Metric = 'DistributionGroups'
        Count  = $distributionGroups.Count
    }
    [PSCustomObject]@{
        Metric = 'M365Groups'
        Count  = $m365Groups.Count
    }
    [PSCustomObject]@{
        Metric = 'TotalItems'
        Count  = $totalItemsDisplay
    }
)

Write-Verbose "Summary complete: $($allMailboxes.Count) mailboxes, $($distributionGroups.Count) DLs, $($m365Groups.Count) M365 groups"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported mailbox summary to $OutputPath"
}
else {
    Write-Output $results
}
