# tests/Behavior/Wrapper-Deprecation.Tests.ps1 -- C3 #782
#
# Regression guard: every legacy Get-M365*SecurityConfig / *RetentionConfig
# wrapper must emit a deprecation Write-Warning at first call. Once-per-session
# semantics: a second call from the same session is silent (a script that
# loops calling the same wrapper shouldn't spam).

BeforeAll {
    # Static check only -- we don't import the module here because the
    # wrappers depend on Microsoft.Graph etc. that may not be installed.
    $script:psm1Path = (Resolve-Path (Join-Path $PSScriptRoot '../../src/M365-Assess/M365-Assess.psm1')).Path
    $script:content  = Get-Content $script:psm1Path -Raw

    # Authoritative list of wrappers slated for removal in v3.0.0.
    $script:wrappers = @(
        'Get-M365ExoSecurityConfig'
        'Get-M365DnsSecurityConfig'
        'Get-M365EntraSecurityConfig'
        'Get-M365CASecurityConfig'
        'Get-M365EntAppSecurityConfig'
        'Get-M365IntuneSecurityConfig'
        'Get-M365DefenderSecurityConfig'
        'Get-M365ComplianceSecurityConfig'
        'Get-M365SharePointSecurityConfig'
        'Get-M365TeamsSecurityConfig'
        'Get-M365FormsSecurityConfig'
        'Get-M365PowerBISecurityConfig'
        'Get-M365PurviewRetentionConfig'
    )
}

Describe 'Wrapper deprecation (C3 #782)' {

    It 'declares Show-WrapperDeprecation helper' {
        $script:content | Should -Match 'function Show-WrapperDeprecation'
    }

    It 'tracks once-per-session via a script-scoped hashtable' {
        # Avoids spamming the warning when a script loops a wrapper 50 times.
        $script:content | Should -Match '\$script:WrapperDeprecationWarned'
    }

    It 'emits a v3.0.0 removal notice in the warning text' {
        $script:content | Should -Match 'will be removed in v3\.0\.0'
        $script:content | Should -Match 'Invoke-M365Assessment -Section'
    }

    It 'every legacy wrapper invokes Show-WrapperDeprecation' {
        $missing = @()
        foreach ($name in $script:wrappers) {
            # The function body for $name should contain the helper call.
            # Simpler form: a regex that captures function-block + helper presence.
            $pattern = "function $([regex]::Escape($name))\s*\{[\s\S]*?Show-WrapperDeprecation -WrapperName '$([regex]::Escape($name))'"
            if ($script:content -notmatch $pattern) {
                $missing += $name
            }
        }
        if ($missing.Count -gt 0) {
            throw "These wrappers are missing the deprecation call:`n$(($missing) -join "`n")"
        }
    }

    It 'every legacy wrapper documents the replacement -Section in .NOTES' {
        $missing = @()
        foreach ($name in $script:wrappers) {
            # The function .NOTES block should contain the migration phrase.
            $pattern = "function $([regex]::Escape($name))\s*\{[\s\S]*?DEPRECATED \(C3 #782\)"
            if ($script:content -notmatch $pattern) {
                $missing += $name
            }
        }
        if ($missing.Count -gt 0) {
            throw "These wrappers are missing the DEPRECATED .NOTES marker:`n$(($missing) -join "`n")"
        }
    }
}
