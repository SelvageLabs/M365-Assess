<#
.SYNOPSIS
    Deterministic PII redaction rules for the sanitized evidence package (D4 #788).
.DESCRIPTION
    Pure function module. Provides Invoke-RedactionRules for stripping
    user-identifiable information from arbitrary text content while preserving
    join keys via SHA-256-truncated tokens.

    Replacements use stable hashes: the same UPN always produces the same
    <user-xxxxxxxx> token across all artifacts in the package. This lets an
    auditor still see correlations ("user-a3f81b29 fails MFA on CA-001 and has
    admin role on ROLE-001") without ever seeing the underlying UPN.

    Categories redacted:
      - UPNs / email addresses        -> <user-{hash}>
      - IPv4 / IPv6 addresses         -> <ip-{hash}>
      - Application/Tenant GUIDs      -> <guid-{hash}>  (preserves GUID structure)

    Tenant display name is redacted via -TenantDisplayName param when the
    caller knows it; we don't try to discover it from text alone since
    "Contoso" inside a control description shouldn't be touched.
.NOTES
    The hash is SHA-256(value) truncated to 8 hex chars. 8 chars * 4 bits =
    32 bits of entropy; for the typical tenant size (<10k principals) the
    collision probability is < 10^-5, well below "useful for join keys" while
    revealing nothing about the underlying value.
#>

function Get-RedactionToken {
    <#
    .SYNOPSIS
        Returns a deterministic redaction token for a single value.
    .PARAMETER Value
        The plaintext value to redact.
    .PARAMETER Prefix
        Token prefix (e.g. 'user', 'ip', 'guid').
    .OUTPUTS
        String of the form '<{prefix}-{8 hex chars}>'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix
    )
    if ([string]::IsNullOrEmpty($Value)) { return "<$Prefix-empty>" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
        $hash  = $sha.ComputeHash($bytes)
        $hex   = -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
        return "<$Prefix-$hex>"
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-RedactionRules {
    <#
    .SYNOPSIS
        Applies the full PII redaction ruleset to a string of text.
    .PARAMETER Text
        Input text. Returned unchanged if empty or null.
    .PARAMETER TenantDisplayName
        Optional. When provided, all case-insensitive occurrences of the
        tenant display name are replaced with <tenant>.
    .OUTPUTS
        Redacted string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text,

        [Parameter()]
        [string]$TenantDisplayName
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $result = $Text

    # Email / UPN pass FIRST. Running tenant-name first would eat the domain
    # portion of any email containing the tenant name (admin@contoso.com ->
    # admin@<tenant>.com), leaving the address half-redacted and undetectable
    # by later regexes. Replacing the whole address with <user-{hash}> first
    # neutralises that risk.
    $emailPattern = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    $result = [regex]::Replace($result, $emailPattern, {
        param($m) Get-RedactionToken -Value $m.Value -Prefix 'user'
    })

    # Tenant display name pass -- runs after email so only bare mentions in
    # narrative text are caught. Case-insensitive.
    if (-not [string]::IsNullOrWhiteSpace($TenantDisplayName)) {
        $escaped = [regex]::Escape($TenantDisplayName)
        $result = [regex]::Replace($result, $escaped, '<tenant>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    # IPv4 (4 octets 0-255). Anchored to word boundaries to avoid matching
    # version strings like 1.2.3.4 inside paths.
    $ipv4Pattern = '\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|\d{1,2})\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|\d{1,2})\b'
    $result = [regex]::Replace($result, $ipv4Pattern, {
        param($m) Get-RedactionToken -Value $m.Value -Prefix 'ip'
    })

    # IPv6: full form (8 colon-separated segments) OR compact form (any
    # segments + :: + any segments). Loose -- catches common shapes without
    # enforcing full RFC 4291 validity.
    $ipv6Full    = '(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}'
    $ipv6Compact = '(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*)?::(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*)?'
    $ipv6Pattern = "(?:$ipv6Full|$ipv6Compact)"
    $result = [regex]::Replace($result, $ipv6Pattern, {
        param($m)
        # Skip false positives: pure '::', single-token, or no hex digits.
        $v = $m.Value
        if ($v -eq '::' -or $v.Length -lt 3) { return $v }
        if ($v -notmatch '[0-9a-fA-F]')      { return $v }
        Get-RedactionToken -Value $v -Prefix 'ip'
    })

    # GUIDs (8-4-4-4-12). Preserve the structural shape so consumers can still
    # spot "this is a GUID" while not seeing the value. Token is shorter than
    # a real GUID, so it's visually distinct.
    $guidPattern = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'
    $result = [regex]::Replace($result, $guidPattern, {
        param($m) Get-RedactionToken -Value $m.Value -Prefix 'guid'
    })

    return $result
}
