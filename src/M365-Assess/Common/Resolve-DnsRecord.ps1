<#
.SYNOPSIS
    Cross-platform DNS record resolver for M365-Assess.

.DESCRIPTION
    Wraps Resolve-DnsName (Windows) and dig (macOS/Linux) behind a unified
    interface so DNS lookups work on any platform.  Returns PSCustomObjects
    with the same property shapes the rest of the codebase expects:
      - TXT  records → .Strings  ([string[]])
      - CNAME records → .NameHost ([string])

.PARAMETER Name
    The DNS name to query (e.g. 'contoso.com', '_dmarc.contoso.com').

.PARAMETER Type
    Record type — TXT or CNAME.

.PARAMETER Server
    Optional DNS server IP to query (e.g. '8.8.8.8').

.PARAMETER DnsOnly
    Accepted for call-site compatibility with Resolve-DnsName but ignored
    on the dig path (dig always uses DNS-only resolution).

.EXAMPLE
    Resolve-DnsRecord -Name contoso.com -Type TXT
    Resolve-DnsRecord -Name '_dmarc.contoso.com' -Type TXT -Server 8.8.8.8
#>
function Resolve-DnsRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('TXT', 'CNAME', 'MX')]
        [string]$Type,

        [string]$Server,

        [switch]$DnsOnly
    )

    # ── One-time backend detection (cached for session) ──────────────
    if ($null -eq $script:DnsBackend) {
        if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
            $script:DnsBackend = 'ResolveDnsName'
        }
        elseif (Get-Command -Name dig -ErrorAction SilentlyContinue) {
            $script:DnsBackend = 'Dig'
        }
        else {
            $script:DnsBackend = 'None'
            Write-Warning 'Resolve-DnsRecord: Neither Resolve-DnsName (Windows) nor dig (macOS/Linux) is available. DNS lookups will be skipped. Install dig via: brew install bind (macOS) or apt install dnsutils (Linux).'
        }
    }

    # ── Windows: delegate to Resolve-DnsName ─────────────────────────
    if ($script:DnsBackend -eq 'ResolveDnsName') {
        $params = @{
            Name        = $Name
            Type        = $Type
            DnsOnly     = $true
            ErrorAction = $ErrorActionPreference
        }
        if ($Server) { $params['Server'] = $Server }
        return @(Resolve-DnsName @params)
    }

    # ── macOS / Linux: parse dig output ──────────────────────────────
    if ($script:DnsBackend -eq 'Dig') {
        $digArgs = @('+short', $Type, $Name)
        if ($Server) { $digArgs = @("@$Server") + $digArgs }

        try {
            $raw = & dig @digArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                if ($ErrorActionPreference -eq 'Stop') {
                    throw "dig query failed for $Name ($Type): $raw"
                }
                return $null
            }

            $lines = @($raw | Where-Object { $_ -and $_ -notmatch '^\s*$' -and $_ -notmatch '^;;' })
            if ($lines.Count -eq 0) {
                return $null
            }

            switch ($Type) {
                'TXT' {
                    foreach ($line in $lines) {
                        # dig +short returns TXT data in quotes, possibly
                        # split across multiple quoted segments on one line.
                        # Reassemble them into a single string array entry
                        # to match Resolve-DnsName .Strings behaviour.
                        $segments = @([regex]::Matches($line, '"([^"]*)"') |
                            ForEach-Object { $_.Groups[1].Value })

                        if ($segments.Count -eq 0) {
                            # Unquoted fallback (shouldn't happen with dig +short TXT)
                            $segments = @($line.Trim())
                        }

                        [PSCustomObject]@{
                            Name    = $Name
                            Type    = 'TXT'
                            Strings = [string[]]$segments
                        }
                    }
                }
                'CNAME' {
                    # dig +short CNAME returns a single line like:
                    #   selector1-contoso._domainkey.contoso.onmicrosoft.com.
                    $target = $lines[0].TrimEnd('.')
                    [PSCustomObject]@{
                        Name     = $Name
                        Type     = 'CNAME'
                        NameHost = $target
                    }
                }
                'MX' {
                    # dig +short MX returns lines like:
                    #   10 contoso-com.mail.protection.outlook.com.
                    foreach ($line in $lines) {
                        $parts = ($line.Trim()) -split '\s+', 2
                        if ($parts.Count -eq 2) {
                            [PSCustomObject]@{
                                Name         = $Name
                                Type         = 'MX'
                                Preference   = [int]$parts[0]
                                NameExchange = $parts[1].TrimEnd('.')
                            }
                        }
                    }
                }
            }
        }
        catch {
            if ($ErrorActionPreference -eq 'Stop') { throw }
            return $null
        }

        return
    }

    # ── No backend available ─────────────────────────────────────────
    if ($ErrorActionPreference -eq 'Stop') {
        throw "No DNS resolution backend available. Cannot resolve $Name ($Type)."
    }
    return $null
}
