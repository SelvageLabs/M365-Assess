<#
.SYNOPSIS
    Audits mailbox permissions across Exchange Online.
.DESCRIPTION
    Retrieves Full Access, Send As, and Send on Behalf permissions for Exchange
    Online mailboxes. Essential for security reviews, onboarding/offboarding audits,
    and compliance reporting. Excludes system accounts (NT AUTHORITY, S-1-5-*) by default.

    Requires ExchangeOnlineManagement module and an active EXO connection.
.PARAMETER Identity
    One or more mailbox identities (UPN or alias) to audit. If not specified,
    all user mailboxes are audited.
.PARAMETER PermissionType
    Which permission types to include: FullAccess, SendAs, SendOnBehalf, or All.
    Defaults to All.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service ExchangeOnline
    PS> .\Exchange-Online\Get-MailboxPermissionReport.ps1

    Audits all permission types on all user mailboxes.
.EXAMPLE
    PS> .\Exchange-Online\Get-MailboxPermissionReport.ps1 -Identity 'jsmith@contoso.com' -PermissionType FullAccess

    Checks only Full Access permissions on a specific mailbox.
.EXAMPLE
    PS> .\Exchange-Online\Get-MailboxPermissionReport.ps1 -OutputPath '.\mailbox-permissions.csv'

    Exports a full mailbox permission audit to CSV.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Identity,

    [Parameter()]
    [ValidateSet('All', 'FullAccess', 'SendAs', 'SendOnBehalf')]
    [string]$PermissionType = 'All',

    [Parameter()]
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

# Get target mailboxes
if ($Identity) {
    $mailboxes = foreach ($id in $Identity) {
        try {
            Get-EXOMailbox -Identity $id -Properties DisplayName, PrimarySmtpAddress, GrantSendOnBehalfTo
        }
        catch {
            Write-Warning "Mailbox not found: $id"
        }
    }
}
else {
    Write-Verbose "Retrieving all user mailboxes..."
    $mailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox -Properties DisplayName, PrimarySmtpAddress, GrantSendOnBehalfTo
}

$mailboxes = @($mailboxes)
Write-Verbose "Processing $($mailboxes.Count) mailboxes..."

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$counter = 0

foreach ($mbx in $mailboxes) {
    $counter++
    Write-Verbose "[$counter/$($mailboxes.Count)] $($mbx.PrimarySmtpAddress)"

    # Full Access permissions
    if ($PermissionType -in 'All', 'FullAccess') {
        try {
            $fullAccessPerms = Get-MailboxPermission -Identity $mbx.PrimarySmtpAddress |
                Where-Object {
                    $_.User -notlike 'NT AUTHORITY\*' -and
                    $_.User -notlike 'S-1-5-*' -and
                    $_.IsInherited -eq $false -and
                    $_.AccessRights -contains 'FullAccess'
                }

            foreach ($perm in $fullAccessPerms) {
                $results.Add([PSCustomObject]@{
                    Mailbox        = $mbx.DisplayName
                    MailboxAddress  = $mbx.PrimarySmtpAddress
                    PermissionType = 'FullAccess'
                    GrantedTo      = $perm.User
                    Inherited      = $perm.IsInherited
                })
            }
        }
        catch {
            Write-Warning "Failed to get FullAccess permissions for $($mbx.PrimarySmtpAddress): $_"
        }
    }

    # Send As permissions
    if ($PermissionType -in 'All', 'SendAs') {
        try {
            $sendAsPerms = Get-RecipientPermission -Identity $mbx.PrimarySmtpAddress |
                Where-Object {
                    $_.Trustee -notlike 'NT AUTHORITY\*' -and
                    $_.Trustee -notlike 'S-1-5-*'
                }

            foreach ($perm in $sendAsPerms) {
                $results.Add([PSCustomObject]@{
                    Mailbox        = $mbx.DisplayName
                    MailboxAddress  = $mbx.PrimarySmtpAddress
                    PermissionType = 'SendAs'
                    GrantedTo      = $perm.Trustee
                    Inherited      = $false
                })
            }
        }
        catch {
            Write-Warning "Failed to get SendAs permissions for $($mbx.PrimarySmtpAddress): $_"
        }
    }

    # Send on Behalf permissions
    if ($PermissionType -in 'All', 'SendOnBehalf') {
        if ($mbx.GrantSendOnBehalfTo.Count -gt 0) {
            foreach ($delegate in $mbx.GrantSendOnBehalfTo) {
                $results.Add([PSCustomObject]@{
                    Mailbox        = $mbx.DisplayName
                    MailboxAddress  = $mbx.PrimarySmtpAddress
                    PermissionType = 'SendOnBehalf'
                    GrantedTo      = $delegate
                    Inherited      = $false
                })
            }
        }
    }
}

Write-Verbose "Found $($results.Count) permission entries across $($mailboxes.Count) mailboxes"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) permission entries to $OutputPath"
}
else {
    Write-Output $results
}
