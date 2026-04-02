BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-MfaReport' {
    BeforeAll {
        # Stub Get-MgContext so the connection check passes
        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }
        # Stub Graph cmdlet so Pester can mock it without the module installed
        function Get-MgReportAuthenticationMethodUserRegistrationDetail { }

        # Stub Import-Module to prevent actual module loading
        Mock Import-Module { }

        # Mock Get-MgReportAuthenticationMethodUserRegistrationDetail with realistic data
        Mock Get-MgReportAuthenticationMethodUserRegistrationDetail {
            return @(
                [PSCustomObject]@{
                    UserPrincipalName     = 'user1@contoso.com'
                    UserDisplayName       = 'User One'
                    IsMfaRegistered       = $true
                    IsMfaCapable          = $true
                    IsPasswordlessCapable = $false
                    IsSsprRegistered      = $true
                    IsSsprCapable         = $true
                    MethodsRegistered     = @('microsoftAuthenticatorPush', 'softwareOneTimePasscode')
                    DefaultMfaMethod      = 'microsoftAuthenticatorPush'
                    IsAdmin               = $false
                },
                [PSCustomObject]@{
                    UserPrincipalName     = 'admin@contoso.com'
                    UserDisplayName       = 'Admin User'
                    IsMfaRegistered       = $true
                    IsMfaCapable          = $true
                    IsPasswordlessCapable = $true
                    IsSsprRegistered      = $true
                    IsSsprCapable         = $true
                    MethodsRegistered     = @('microsoftAuthenticatorPush', 'fido2')
                    DefaultMfaMethod      = 'microsoftAuthenticatorPush'
                    IsAdmin               = $true
                },
                [PSCustomObject]@{
                    UserPrincipalName     = 'nomfa@contoso.com'
                    UserDisplayName       = 'No MFA User'
                    IsMfaRegistered       = $false
                    IsMfaCapable          = $false
                    IsPasswordlessCapable = $false
                    IsSsprRegistered      = $false
                    IsSsprCapable         = $false
                    MethodsRegistered     = @()
                    DefaultMfaMethod      = ''
                    IsAdmin               = $false
                }
            )
        }

        # Run the collector
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        $result = & "$PSScriptRoot/../../src/M365-Assess/Entra/Get-MfaReport.ps1"
    }

    It 'Returns a non-empty MFA report' {
        $result | Should -Not -BeNullOrEmpty
    }

    It 'Output has expected properties' {
        $first = $result | Select-Object -First 1
        $first.PSObject.Properties.Name | Should -Contain 'UserPrincipalName'
        $first.PSObject.Properties.Name | Should -Contain 'IsMfaRegistered'
        $first.PSObject.Properties.Name | Should -Contain 'IsMfaCapable'
        $first.PSObject.Properties.Name | Should -Contain 'MethodsRegistered'
        $first.PSObject.Properties.Name | Should -Contain 'DefaultMfaMethod'
        $first.PSObject.Properties.Name | Should -Contain 'IsAdmin'
    }

    It 'Returns one row per user' {
        @($result).Count | Should -Be 3
    }

    It 'Joins methods into semicolon-delimited string' {
        $user1 = $result | Where-Object { $_.UserPrincipalName -eq 'user1@contoso.com' }
        $user1.MethodsRegistered | Should -Match 'microsoftAuthenticatorPush'
        $user1.MethodsRegistered | Should -Match ';'
    }

    It 'Output has MfaStrength property' {
        $first = $result | Select-Object -First 1
        $first.PSObject.Properties.Name | Should -Contain 'MfaStrength'
    }

    It 'Classifies phishing-resistant MFA correctly' {
        $admin = $result | Where-Object { $_.UserPrincipalName -eq 'admin@contoso.com' }
        $admin.MfaStrength | Should -Be 'Phishing-Resistant'
    }

    It 'Classifies standard MFA correctly' {
        $user1 = $result | Where-Object { $_.UserPrincipalName -eq 'user1@contoso.com' }
        $user1.MfaStrength | Should -Be 'Standard'
    }

    It 'Classifies no-MFA users as None' {
        $noMfa = $result | Where-Object { $_.UserPrincipalName -eq 'nomfa@contoso.com' }
        $noMfa.MfaStrength | Should -Be 'None'
    }
}

Describe 'Get-MfaMethodStrength' {
    BeforeAll {
        # Stub dependencies so we can dot-source for the function definition
        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }
        function Get-MgReportAuthenticationMethodUserRegistrationDetail { }
        Mock Import-Module { }
        Mock Get-MgReportAuthenticationMethodUserRegistrationDetail { return @() }
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
        . "$PSScriptRoot/../../src/M365-Assess/Entra/Get-MfaReport.ps1"
    }

    It 'Returns Phishing-Resistant for FIDO2' {
        Get-MfaMethodStrength -Methods @('fido2') | Should -Be 'Phishing-Resistant'
    }

    It 'Returns Phishing-Resistant for Windows Hello' {
        Get-MfaMethodStrength -Methods @('windowsHelloForBusiness') | Should -Be 'Phishing-Resistant'
    }

    It 'Returns Phishing-Resistant when mixed with weaker methods' {
        Get-MfaMethodStrength -Methods @('mobilePhone', 'fido2', 'softwareOneTimePasscode') | Should -Be 'Phishing-Resistant'
    }

    It 'Returns Standard for Authenticator push' {
        Get-MfaMethodStrength -Methods @('microsoftAuthenticatorPush') | Should -Be 'Standard'
    }

    It 'Returns Standard for TOTP' {
        Get-MfaMethodStrength -Methods @('softwareOneTimePasscode') | Should -Be 'Standard'
    }

    It 'Returns Weak for SMS only' {
        Get-MfaMethodStrength -Methods @('mobilePhone') | Should -Be 'Weak'
    }

    It 'Returns None for empty array' {
        Get-MfaMethodStrength -Methods @() | Should -Be 'None'
    }

    It 'Returns None for null' {
        Get-MfaMethodStrength -Methods $null | Should -Be 'None'
    }

    It 'Returns Unknown for unrecognized method' {
        Get-MfaMethodStrength -Methods @('someNewMethod') | Should -Be 'Unknown'
    }
}

Describe 'Get-MfaReport - Edge Cases' {
    BeforeAll {
        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }
        function Get-MgReportAuthenticationMethodUserRegistrationDetail { }
        Mock Import-Module { }
    }

    Context 'when no MFA registration details are returned' {
        BeforeAll {
            Mock Get-MgReportAuthenticationMethodUserRegistrationDetail { return @() }
            . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
            $result = & "$PSScriptRoot/../../src/M365-Assess/Entra/Get-MfaReport.ps1"
        }

        It 'Returns empty result without error' {
            $result | Should -BeNullOrEmpty
        }
    }
}
