<#
.SYNOPSIS
    Searches the Microsoft 365 unified audit log.
.DESCRIPTION
    Wraps Search-UnifiedAuditLog with a friendlier interface for common
    investigation scenarios. Handles pagination automatically and returns
    parsed audit records. Essential for incident response, compliance
    investigations, and answering "who did what and when" questions.

    Requires ExchangeOnlineManagement module and an active Purview/Compliance
    connection (Connect-IPPSSession).
.PARAMETER StartDate
    Start of the search window. Required.
.PARAMETER EndDate
    End of the search window. Defaults to the current date/time.
.PARAMETER UserIds
    One or more UPNs to filter by. If not specified, searches all users.
.PARAMETER Operations
    One or more audit operations to filter by (e.g., 'FileAccessed',
    'MailItemsAccessed', 'UserLoggedIn', 'Add member to role.').
.PARAMETER RecordType
    Audit record type filter (e.g., 'AzureActiveDirectory', 'ExchangeAdmin',
    'SharePointFileOperation'). If not specified, all record types are searched.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service Purview
    PS> .\Purview\Search-AuditLog.ps1 -StartDate '2026-02-01' -EndDate '2026-03-01'

    Searches all audit records for the month of February 2026.
.EXAMPLE
    PS> .\Purview\Search-AuditLog.ps1 -StartDate '2026-03-01' -UserIds 'jsmith@contoso.com' -Operations 'FileAccessed','FileDownloaded'

    Searches for file access activity by a specific user since March 1.
.EXAMPLE
    PS> .\Purview\Search-AuditLog.ps1 -StartDate '2026-02-15' -RecordType 'AzureActiveDirectory' -OutputPath '.\entra-audit.csv'

    Exports Entra ID audit events to CSV.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [datetime]$StartDate,

    [Parameter()]
    [datetime]$EndDate = (Get-Date),

    [Parameter()]
    [string[]]$UserIds,

    [Parameter()]
    [string[]]$Operations,

    [Parameter()]
    [string]$RecordType,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify compliance connection by testing the cmdlet
try {
    $null = Get-Command -Name Search-UnifiedAuditLog -ErrorAction Stop
}
catch {
    Write-Error "Search-UnifiedAuditLog is not available. Run Connect-Service -Service Purview first."
    return
}

Write-Verbose "Searching audit log from $($StartDate.ToString('yyyy-MM-dd HH:mm')) to $($EndDate.ToString('yyyy-MM-dd HH:mm'))"

$searchParams = @{
    StartDate  = $StartDate
    EndDate    = $EndDate
    ResultSize = 5000
}

if ($UserIds) {
    $searchParams['UserIds'] = $UserIds
    Write-Verbose "Filtering by users: $($UserIds -join ', ')"
}

if ($Operations) {
    $searchParams['Operations'] = $Operations
    Write-Verbose "Filtering by operations: $($Operations -join ', ')"
}

if ($RecordType) {
    $searchParams['RecordType'] = $RecordType
    Write-Verbose "Filtering by record type: $RecordType"
}

# Paginate through results
$allRecords = [System.Collections.Generic.List[PSCustomObject]]::new()
$sessionId = [guid]::NewGuid().ToString()
$searchParams['SessionId'] = $sessionId
$searchParams['SessionCommand'] = 'ReturnLargeSet'

try {
    $page = 0
    do {
        $page++
        Write-Verbose "Retrieving page $page..."

        $batch = Search-UnifiedAuditLog @searchParams

        if ($null -eq $batch -or $batch.Count -eq 0) {
            break
        }

        foreach ($record in $batch) {
            $auditData = $record.AuditData | ConvertFrom-Json

            $allRecords.Add([PSCustomObject]@{
                CreationDate   = $record.CreationDate
                UserIds        = $record.UserIds
                Operations     = $record.Operations
                RecordType     = $record.RecordType
                ResultIndex    = $record.ResultIndex
                ResultCount    = $record.ResultCount
                ClientIP       = $auditData.ClientIP
                ObjectId       = $auditData.ObjectId
                ItemType       = $auditData.ItemType
                SiteUrl        = $auditData.SiteUrl
                SourceFileName = $auditData.SourceFileName
                AuditData      = $record.AuditData
            })
        }

        Write-Verbose "Retrieved $($allRecords.Count) of $($batch[0].ResultCount) total records"

        # Stop if we've retrieved all results
        if ($allRecords.Count -ge $batch[0].ResultCount) {
            break
        }

    } while ($true)
}
catch {
    Write-Error "Audit log search failed: $_"
    return
}

Write-Verbose "Total records found: $($allRecords.Count)"

if ($OutputPath) {
    $allRecords | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($allRecords.Count) audit records to $OutputPath"
}
else {
    Write-Output $allRecords
}
