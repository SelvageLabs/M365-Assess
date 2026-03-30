<#
.SYNOPSIS
    Reports Active Directory security posture including password policies and privileged groups.
.DESCRIPTION
    Collects the default domain password policy, any fine-grained password policies,
    and membership of privileged built-in groups (Domain Admins, Enterprise Admins,
    Schema Admins, Administrators, Backup Operators, Account Operators).

    Also identifies user accounts with security-relevant flags: PasswordNeverExpires,
    PasswordNotRequired, and AllowReversiblePasswordEncryption.

    Designed for IT consultants performing AD assessments on SMB environments
    (10-500 users). All operations are read-only.

    Requires the ActiveDirectory module (available via RSAT or on domain controllers).
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADSecurityReport.ps1

    Returns password policies, privileged group members, and flagged accounts.
.EXAMPLE
    PS> .\ActiveDirectory\Get-ADSecurityReport.ps1 -OutputPath '.\ad-security.csv'

    Exports the security report to CSV.
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
# Default Domain Password Policy
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying default domain password policy..."
    $policy = Get-ADDefaultDomainPasswordPolicy

    $report.Add([PSCustomObject]@{
        RecordType    = 'PasswordPolicy'
        Category      = 'Default Domain Policy'
        Name          = 'Default Domain Password Policy'
        Value         = ''
        RiskLevel     = 'Info'
        Detail        = @(
            "MinPasswordLength=$($policy.MinPasswordLength)"
            "MaxPasswordAge=$($policy.MaxPasswordAge)"
            "MinPasswordAge=$($policy.MinPasswordAge)"
            "PasswordHistoryCount=$($policy.PasswordHistoryCount)"
            "ComplexityEnabled=$($policy.ComplexityEnabled)"
            "ReversibleEncryption=$($policy.ReversibleEncryptionEnabled)"
            "LockoutThreshold=$($policy.LockoutThreshold)"
            "LockoutDuration=$($policy.LockoutDuration)"
            "LockoutObservationWindow=$($policy.LockoutObservationWindow)"
        ) -join '; '
    })

    # Flag weak password policy settings
    if ($policy.MinPasswordLength -lt 8) {
        $report.Add([PSCustomObject]@{
            RecordType = 'PasswordPolicy'
            Category   = 'Default Domain Policy'
            Name       = 'Weak minimum password length'
            Value      = "$($policy.MinPasswordLength) characters"
            RiskLevel  = 'High'
            Detail     = "Minimum password length is $($policy.MinPasswordLength). Recommended: 14 or higher."
        })
    }

    if (-not $policy.ComplexityEnabled) {
        $report.Add([PSCustomObject]@{
            RecordType = 'PasswordPolicy'
            Category   = 'Default Domain Policy'
            Name       = 'Password complexity disabled'
            Value      = 'False'
            RiskLevel  = 'High'
            Detail     = 'Password complexity requirements are disabled.'
        })
    }

    if ($policy.LockoutThreshold -eq 0) {
        $report.Add([PSCustomObject]@{
            RecordType = 'PasswordPolicy'
            Category   = 'Default Domain Policy'
            Name       = 'No account lockout configured'
            Value      = '0'
            RiskLevel  = 'High'
            Detail     = 'Account lockout threshold is 0 (disabled). Accounts are vulnerable to brute force.'
        })
    }

    if ($policy.ReversibleEncryptionEnabled) {
        $report.Add([PSCustomObject]@{
            RecordType = 'PasswordPolicy'
            Category   = 'Default Domain Policy'
            Name       = 'Reversible encryption enabled'
            Value      = 'True'
            RiskLevel  = 'Critical'
            Detail     = 'Reversible encryption stores passwords in a recoverable form. This should be disabled.'
        })
    }

    Write-Verbose "Default domain password policy collected"
}
catch {
    Write-Warning "Failed to query default domain password policy: $_"
}

# ------------------------------------------------------------------
# Fine-Grained Password Policies
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying fine-grained password policies..."
    $fgPolicies = @(Get-ADFineGrainedPasswordPolicy -Filter *)

    foreach ($fgp in $fgPolicies) {
        $appliesTo = if ($fgp.AppliesTo) {
            ($fgp.AppliesTo | ForEach-Object {
                if ($_ -match '^CN=([^,]+),') { $Matches[1] } else { $_ }
            }) -join '; '
        }
        else { 'None' }

        $report.Add([PSCustomObject]@{
            RecordType = 'PasswordPolicy'
            Category   = 'Fine-Grained Policy'
            Name       = $fgp.Name
            Value      = "Precedence=$($fgp.Precedence)"
            RiskLevel  = 'Info'
            Detail     = @(
                "MinPasswordLength=$($fgp.MinPasswordLength)"
                "MaxPasswordAge=$($fgp.MaxPasswordAge)"
                "PasswordHistoryCount=$($fgp.PasswordHistoryCount)"
                "ComplexityEnabled=$($fgp.ComplexityEnabled)"
                "LockoutThreshold=$($fgp.LockoutThreshold)"
                "AppliesTo=$appliesTo"
            ) -join '; '
        })
    }

    if ($fgPolicies.Count -eq 0) {
        Write-Verbose "No fine-grained password policies found"
    }
    else {
        Write-Verbose "Found $($fgPolicies.Count) fine-grained password policy(ies)"
    }
}
catch {
    Write-Warning "Failed to query fine-grained password policies: $_"
}

# ------------------------------------------------------------------
# Privileged Group Membership
# ------------------------------------------------------------------
$privilegedGroups = @(
    'Domain Admins'
    'Enterprise Admins'
    'Schema Admins'
    'Administrators'
    'Backup Operators'
    'Account Operators'
)

foreach ($groupName in $privilegedGroups) {
    try {
        Write-Verbose "Querying members of $groupName..."
        $members = @(Get-ADGroupMember -Identity $groupName -ErrorAction Stop)

        if ($members.Count -eq 0) {
            $report.Add([PSCustomObject]@{
                RecordType = 'PrivilegedGroup'
                Category   = 'Group Membership'
                Name       = $groupName
                Value      = '0 members'
                RiskLevel  = 'Info'
                Detail     = 'No members'
            })
            continue
        }

        $riskLevel = if ($members.Count -gt 5) { 'Warning' } else { 'Info' }

        $memberList = ($members | ForEach-Object { $_.SamAccountName }) -join '; '

        $report.Add([PSCustomObject]@{
            RecordType = 'PrivilegedGroup'
            Category   = 'Group Membership'
            Name       = $groupName
            Value      = "$($members.Count) members"
            RiskLevel  = $riskLevel
            Detail     = "Members=$memberList"
        })
    }
    catch {
        Write-Warning "Failed to query group '$groupName': $_"
    }
}

# ------------------------------------------------------------------
# Flagged User Accounts (security-relevant attributes)
# ------------------------------------------------------------------
try {
    Write-Verbose "Querying accounts with PasswordNeverExpires..."
    $neverExpires = @(Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } -Properties PasswordNeverExpires)

    if ($neverExpires.Count -gt 0) {
        $accountList = ($neverExpires | ForEach-Object { $_.SamAccountName }) -join '; '
        $riskLevel = if ($neverExpires.Count -gt 10) { 'High' } else { 'Warning' }

        $report.Add([PSCustomObject]@{
            RecordType = 'FlaggedAccounts'
            Category   = 'Password Never Expires'
            Name       = 'Enabled accounts with PasswordNeverExpires'
            Value      = "$($neverExpires.Count) accounts"
            RiskLevel  = $riskLevel
            Detail     = "Accounts=$accountList"
        })
    }
}
catch {
    Write-Warning "Failed to query PasswordNeverExpires accounts: $_"
}

try {
    Write-Verbose "Querying accounts with PasswordNotRequired..."
    $noPassword = @(Get-ADUser -Filter { PasswordNotRequired -eq $true -and Enabled -eq $true } -Properties PasswordNotRequired)

    if ($noPassword.Count -gt 0) {
        $accountList = ($noPassword | ForEach-Object { $_.SamAccountName }) -join '; '

        $report.Add([PSCustomObject]@{
            RecordType = 'FlaggedAccounts'
            Category   = 'Password Not Required'
            Name       = 'Enabled accounts with PasswordNotRequired'
            Value      = "$($noPassword.Count) accounts"
            RiskLevel  = 'Critical'
            Detail     = "Accounts=$accountList"
        })
    }
}
catch {
    Write-Warning "Failed to query PasswordNotRequired accounts: $_"
}

try {
    Write-Verbose "Querying accounts with reversible encryption..."
    $reversible = @(Get-ADUser -Filter { AllowReversiblePasswordEncryption -eq $true -and Enabled -eq $true } -Properties AllowReversiblePasswordEncryption)

    if ($reversible.Count -gt 0) {
        $accountList = ($reversible | ForEach-Object { $_.SamAccountName }) -join '; '

        $report.Add([PSCustomObject]@{
            RecordType = 'FlaggedAccounts'
            Category   = 'Reversible Encryption'
            Name       = 'Enabled accounts with reversible encryption'
            Value      = "$($reversible.Count) accounts"
            RiskLevel  = 'Critical'
            Detail     = "Accounts=$accountList"
        })
    }
}
catch {
    Write-Warning "Failed to query reversible encryption accounts: $_"
}

# ------------------------------------------------------------------
# Export or return
# ------------------------------------------------------------------
$results = @($report)

Write-Verbose "Collected $($results.Count) AD security records"

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($results.Count) AD security records to $OutputPath"
}
else {
    Write-Output $results
}
