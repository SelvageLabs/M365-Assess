<#
.SYNOPSIS
    Reports Safe Links and Safe Attachments policies from Microsoft Defender for Office 365.
.DESCRIPTION
    Retrieves all Safe Links and Safe Attachments policies configured in the tenant
    and produces a unified report showing policy type, enabled state, priority, and
    key configuration settings. Useful for security assessments, baseline reviews,
    and verifying Defender for Office 365 protection is properly configured.

    Handles tenants where Defender for Office 365 is not licensed by skipping
    unavailable cmdlets gracefully.

    Requires ExchangeOnlineManagement module and an active Exchange Online connection.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service ExchangeOnline
    PS> .\Security\Get-DefenderPolicyReport.ps1

    Displays all Safe Links and Safe Attachments policies in the tenant.
.EXAMPLE
    PS> .\Security\Get-DefenderPolicyReport.ps1 -OutputPath '.\defender-policies.csv'

    Exports all Defender for Office 365 policies to CSV.
.EXAMPLE
    PS> .\Security\Get-DefenderPolicyReport.ps1 -Verbose

    Displays policies with verbose processing details, including skip messages for
    unlicensed features.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify Exchange Online connection
try {
    $null = Get-OrganizationConfig -ErrorAction Stop
}
catch {
    Write-Error "Not connected to Exchange Online. Run Connect-Service -Service ExchangeOnline first."
    return
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# --- Safe Links Policies ---
$safeLinksAvailable = $true
try {
    $null = Get-Command -Name Get-SafeLinksPolicy -ErrorAction Stop
}
catch {
    $safeLinksAvailable = $false
    Write-Warning "Get-SafeLinksPolicy cmdlet not found. Defender for Office 365 (Safe Links) may not be licensed for this tenant. Skipping Safe Links policies."
}

if ($safeLinksAvailable) {
    Write-Verbose "Retrieving Safe Links policies..."
    try {
        $safeLinksPolices = Get-SafeLinksPolicy -ErrorAction Stop

        if (-not $safeLinksPolices -or @($safeLinksPolices).Count -eq 0) {
            Write-Verbose "No Safe Links policies found."
        }
        else {
            foreach ($policy in @($safeLinksPolices)) {
                $keySettings = @(
                    "IsEnabled=$($policy.IsEnabled)"
                    "DoNotTrackUserClicks=$($policy.DoNotTrackUserClicks)"
                    "ScanUrls=$($policy.ScanUrls)"
                    "EnableForInternalSenders=$($policy.EnableForInternalSenders)"
                ) -join '; '

                $results.Add([PSCustomObject]@{
                    PolicyType  = 'SafeLinks'
                    Name        = $policy.Name
                    Enabled     = $policy.IsEnabled
                    Priority    = if ($null -ne $policy.Priority) { $policy.Priority } else { 'N/A' }
                    KeySettings = $keySettings
                })
            }
            Write-Verbose "Found $(@($safeLinksPolices).Count) Safe Links policies."
        }
    }
    catch {
        Write-Warning "Failed to retrieve Safe Links policies: $_"
    }
}

# --- Safe Attachments Policies ---
$safeAttachmentsAvailable = $true
try {
    $null = Get-Command -Name Get-SafeAttachmentPolicy -ErrorAction Stop
}
catch {
    $safeAttachmentsAvailable = $false
    Write-Warning "Get-SafeAttachmentPolicy cmdlet not found. Defender for Office 365 (Safe Attachments) may not be licensed for this tenant. Skipping Safe Attachments policies."
}

if ($safeAttachmentsAvailable) {
    Write-Verbose "Retrieving Safe Attachments policies..."
    try {
        $safeAttachmentPolicies = Get-SafeAttachmentPolicy -ErrorAction Stop

        if (-not $safeAttachmentPolicies -or @($safeAttachmentPolicies).Count -eq 0) {
            Write-Verbose "No Safe Attachments policies found."
        }
        else {
            foreach ($policy in @($safeAttachmentPolicies)) {
                $keySettings = @(
                    "Enable=$($policy.Enable)"
                    "Action=$($policy.Action)"
                    "Redirect=$($policy.Redirect)"
                    "RedirectAddress=$($policy.RedirectAddress)"
                ) -join '; '

                $results.Add([PSCustomObject]@{
                    PolicyType  = 'SafeAttachments'
                    Name        = $policy.Name
                    Enabled     = $policy.Enable
                    Priority    = if ($null -ne $policy.Priority) { $policy.Priority } else { 'N/A' }
                    KeySettings = $keySettings
                })
            }
            Write-Verbose "Found $(@($safeAttachmentPolicies).Count) Safe Attachments policies."
        }
    }
    catch {
        Write-Warning "Failed to retrieve Safe Attachments policies: $_"
    }
}

# Output results
if ($results.Count -eq 0) {
    Write-Warning "No Defender for Office 365 policies found. Verify that the tenant is licensed for Microsoft Defender for Office 365."
    return
}

Write-Verbose "Total policies found: $($results.Count)"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) Defender for Office 365 policies to $OutputPath"
}
else {
    Write-Output $results
}
