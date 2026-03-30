<#
.SYNOPSIS
    Reports audit log configuration and retention policies from Microsoft Purview.
.DESCRIPTION
    Retrieves the admin audit log configuration and unified audit log retention
    policies using Exchange Online / Purview cmdlets. Reports whether audit logging
    is enabled, the unified audit log ingestion status, and any configured retention
    policies with their durations.

    Essential for compliance assessments, security audits, and verifying that audit
    data is being retained per organizational or regulatory requirements.

    Requires an active Exchange Online / Purview connection (Connect-IPPSSession or
    Connect-ExchangeOnline) with sufficient permissions.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service ExchangeOnline
    PS> .\Purview\Get-AuditRetentionReport.ps1

    Displays audit log config and retention policies in the console.
.EXAMPLE
    PS> .\Purview\Get-AuditRetentionReport.ps1 -OutputPath '.\audit-retention-report.csv'

    Exports audit configuration and retention policies to CSV for compliance documentation.
.EXAMPLE
    PS> Connect-IPPSSession
    PS> .\Purview\Get-AuditRetentionReport.ps1 -Verbose

    Uses a direct Purview connection and shows verbose progress output.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify EXO/Purview connection by testing the audit config cmdlet
$auditConfig = $null
try {
    Write-Verbose "Verifying Exchange Online / Purview connection..."
    $auditConfig = Get-AdminAuditLogConfig -ErrorAction Stop
}
catch {
    $cmdAvailable = Get-Command -Name Get-AdminAuditLogConfig -ErrorAction SilentlyContinue
    if (-not $cmdAvailable) {
        Write-Error "Get-AdminAuditLogConfig is not available. Connect to Exchange Online or Purview first (Connect-Service -Service ExchangeOnline or Connect-IPPSSession)."
        return
    }
    else {
        Write-Error "Failed to retrieve admin audit log config: $_"
        return
    }
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Process audit log configuration
Write-Verbose "Processing admin audit log configuration..."

$unifiedAuditEnabled = $null
if ($auditConfig.PSObject.Properties.Name -contains 'UnifiedAuditLogIngestionEnabled') {
    $unifiedAuditEnabled = $auditConfig.UnifiedAuditLogIngestionEnabled
}

$adminAuditEnabled = $null
if ($auditConfig.PSObject.Properties.Name -contains 'AdminAuditLogEnabled') {
    $adminAuditEnabled = $auditConfig.AdminAuditLogEnabled
}

$configDetails = @()
if ($auditConfig.PSObject.Properties.Name -contains 'AdminAuditLogAgeLimit') {
    $configDetails += "AdminAuditLogAgeLimit=$($auditConfig.AdminAuditLogAgeLimit)"
}
if ($auditConfig.PSObject.Properties.Name -contains 'AdminAuditLogCmdlets') {
    $cmdletSetting = $auditConfig.AdminAuditLogCmdlets -join '; '
    $configDetails += "LoggedCmdlets=$cmdletSetting"
}

$results.Add([PSCustomObject]@{
    ItemType                        = 'AuditConfig'
    Name                            = 'AdminAuditLogConfig'
    UnifiedAuditLogIngestionEnabled = $unifiedAuditEnabled
    AdminAuditLogEnabled            = $adminAuditEnabled
    Details                         = ($configDetails -join ' | ')
})

# Retrieve unified audit log retention policies
$retentionPoliciesAvailable = $true
try {
    Write-Verbose "Retrieving unified audit log retention policies..."
    $retentionPolicies = Get-UnifiedAuditLogRetentionPolicy -ErrorAction Stop
}
catch {
    $cmdAvailable = Get-Command -Name Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue
    if (-not $cmdAvailable) {
        Write-Warning "Get-UnifiedAuditLogRetentionPolicy is not available. The tenant may not have Microsoft 365 E5 or Purview Audit (Premium). Skipping retention policies."
        $retentionPoliciesAvailable = $false
    }
    else {
        Write-Warning "Failed to retrieve unified audit log retention policies: $_"
        $retentionPoliciesAvailable = $false
    }
}

if ($retentionPoliciesAvailable -and $retentionPolicies) {
    $policyList = @($retentionPolicies)
    Write-Verbose "Found $($policyList.Count) audit log retention policy/policies"

    foreach ($policy in $policyList) {
        $policyDetails = @()

        if ($policy.PSObject.Properties.Name -contains 'RetentionDuration') {
            $policyDetails += "RetentionDuration=$($policy.RetentionDuration)"
        }
        if ($policy.PSObject.Properties.Name -contains 'RecordTypes') {
            $recordTypes = if ($policy.RecordTypes) { ($policy.RecordTypes -join '; ') } else { 'All' }
            $policyDetails += "RecordTypes=$recordTypes"
        }
        if ($policy.PSObject.Properties.Name -contains 'Operations') {
            $operations = if ($policy.Operations) { ($policy.Operations -join '; ') } else { 'All' }
            $policyDetails += "Operations=$operations"
        }
        if ($policy.PSObject.Properties.Name -contains 'UserIds') {
            $userIds = if ($policy.UserIds) { ($policy.UserIds -join '; ') } else { 'All' }
            $policyDetails += "UserIds=$userIds"
        }
        if ($policy.PSObject.Properties.Name -contains 'Priority') {
            $policyDetails += "Priority=$($policy.Priority)"
        }
        if ($policy.PSObject.Properties.Name -contains 'Enabled') {
            $policyDetails += "Enabled=$($policy.Enabled)"
        }

        $policyName = if ($policy.PSObject.Properties.Name -contains 'Name') {
            $policy.Name
        }
        elseif ($policy.PSObject.Properties.Name -contains 'Identity') {
            $policy.Identity
        }
        else {
            'UnnamedPolicy'
        }

        $results.Add([PSCustomObject]@{
            ItemType                        = 'RetentionPolicy'
            Name                            = $policyName
            UnifiedAuditLogIngestionEnabled = $null
            AdminAuditLogEnabled            = $null
            Details                         = ($policyDetails -join ' | ')
        })
    }
}
elseif ($retentionPoliciesAvailable -and -not $retentionPolicies) {
    Write-Verbose "No unified audit log retention policies found in the tenant"

    $results.Add([PSCustomObject]@{
        ItemType                        = 'RetentionPolicy'
        Name                            = '(none configured)'
        UnifiedAuditLogIngestionEnabled = $null
        AdminAuditLogEnabled            = $null
        Details                         = 'No custom audit log retention policies are configured. Default retention applies.'
    })
}

$report = @($results)

Write-Verbose "Compiled $($report.Count) audit configuration and retention policy record(s)"

if ($OutputPath) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported audit retention report ($($report.Count) record(s)) to $OutputPath"
}
else {
    Write-Output $report
}
