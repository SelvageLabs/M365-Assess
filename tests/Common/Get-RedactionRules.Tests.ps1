BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/M365-Assess/Common/Get-RedactionRules.ps1')
}

Describe 'Get-RedactionToken (D4 #788)' {
    It 'produces deterministic tokens (same input -> same output)' {
        $a = Get-RedactionToken -Value 'alice@contoso.com' -Prefix 'user'
        $b = Get-RedactionToken -Value 'alice@contoso.com' -Prefix 'user'
        $a | Should -Be $b
    }

    It 'is case-insensitive on the input value (UPNs are case-insensitive in M365)' {
        $a = Get-RedactionToken -Value 'Alice@Contoso.com' -Prefix 'user'
        $b = Get-RedactionToken -Value 'alice@contoso.com' -Prefix 'user'
        $a | Should -Be $b
    }

    It 'produces different tokens for different inputs' {
        $a = Get-RedactionToken -Value 'alice@contoso.com' -Prefix 'user'
        $b = Get-RedactionToken -Value 'bob@contoso.com'   -Prefix 'user'
        $a | Should -Not -Be $b
    }

    It 'uses the requested prefix' {
        Get-RedactionToken -Value 'x' -Prefix 'user' | Should -Match '^<user-[0-9a-f]{8}>$'
        Get-RedactionToken -Value 'x' -Prefix 'ip'   | Should -Match '^<ip-[0-9a-f]{8}>$'
        Get-RedactionToken -Value 'x' -Prefix 'guid' | Should -Match '^<guid-[0-9a-f]{8}>$'
    }
}

Describe 'Invoke-RedactionRules (D4 #788)' {

    Context 'UPN / email redaction' {
        It 'replaces a UPN with a deterministic user-hash token' {
            $out = Invoke-RedactionRules -Text 'Failed signin: alice@contoso.com from outside.'
            $out | Should -Match '<user-[0-9a-f]{8}>'
            $out | Should -Not -Match 'alice@contoso\.com'
        }

        It 'preserves correlation across multiple occurrences (same UPN -> same token)' {
            $text = 'alice@contoso.com is admin. alice@contoso.com also failed MFA.'
            $out  = Invoke-RedactionRules -Text $text
            # Expect the same token both times -- count occurrences of the pattern
            $matches = [regex]::Matches($out, '<user-[0-9a-f]{8}>')
            $matches.Count | Should -Be 2
            $matches[0].Value | Should -Be $matches[1].Value
        }
    }

    Context 'IP redaction' {
        It 'redacts IPv4 addresses' {
            $out = Invoke-RedactionRules -Text 'Connection from 10.20.30.40 blocked.'
            $out | Should -Match '<ip-[0-9a-f]{8}>'
            $out | Should -Not -Match '10\.20\.30\.40'
        }

        It 'redacts IPv6 addresses (compact form)' {
            $out = Invoke-RedactionRules -Text 'Source: 2001:db8::1 routed.'
            $out | Should -Match '<ip-[0-9a-f]{8}>'
        }

        It 'does NOT redact timestamp-like sequences (12:34:56)' {
            $out = Invoke-RedactionRules -Text 'Logged at 12:34:56 today.'
            $out | Should -Be 'Logged at 12:34:56 today.'
        }
    }

    Context 'GUID redaction' {
        It 'redacts GUIDs but preserves the guid-hash shape so consumers know it was a GUID' {
            $out = Invoke-RedactionRules -Text 'AppId: 11111111-2222-3333-4444-555555555555 found.'
            $out | Should -Match '<guid-[0-9a-f]{8}>'
            $out | Should -Not -Match '11111111-2222-3333-4444-555555555555'
        }
    }

    Context 'Tenant display name redaction' {
        It 'replaces case-insensitive occurrences of the tenant name with <tenant>' {
            $out = Invoke-RedactionRules -Text 'CONTOSO is the tenant. contoso failed audit.' -TenantDisplayName 'Contoso'
            $out | Should -Match '<tenant>.*<tenant>'
            $out | Should -Not -Match 'CONTOSO|contoso'
        }

        It 'leaves the text unchanged when no tenant name is provided and no other PII matches' {
            Invoke-RedactionRules -Text 'No PII here.' | Should -Be 'No PII here.'
        }
    }

    Context 'edge cases' {
        It 'returns an empty string unchanged' {
            Invoke-RedactionRules -Text '' | Should -Be ''
        }

        It 'returns null unchanged' {
            Invoke-RedactionRules -Text $null | Should -BeNullOrEmpty
        }

        It 'leaves text without any PII unchanged' {
            $clean = 'Pass: Modern Authentication enabled.'
            Invoke-RedactionRules -Text $clean | Should -Be $clean
        }
    }
}
