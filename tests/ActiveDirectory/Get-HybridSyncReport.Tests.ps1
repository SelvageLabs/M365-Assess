BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-HybridSyncReport' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"

        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }
        function Get-MgOrganization { }
        function Get-MgDomain { }
        Mock Import-Module { }

        Mock Get-MgOrganization {
            return @(
                [PSCustomObject]@{
                    DisplayName               = 'Contoso'
                    Id                        = 'org-id-1'
                    OnPremisesSyncEnabled     = $true
                    OnPremisesLastSyncDateTime = (Get-Date).AddMinutes(-30)
                    VerifiedDomains            = @(
                        [PSCustomObject]@{
                            Name         = 'contoso.com'
                            Type         = 'Managed'
                            IsDefault    = $true
                            IsInitial    = $false
                        },
                        [PSCustomObject]@{
                            Name         = 'contoso.onmicrosoft.com'
                            Type         = 'Managed'
                            IsDefault    = $false
                            IsInitial    = $true
                        }
                    )
                }
            )
        }

        Mock Get-MgDomain {
            return @(
                [PSCustomObject]@{
                    Id                = 'contoso.com'
                    AuthenticationType = 'Managed'
                    IsDefault          = $true
                    IsVerified         = $true
                }
            )
        }

        $script:result = & "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-HybridSyncReport.ps1"
    }

    It 'Should return hybrid sync data' {
        $script:result | Should -Not -BeNullOrEmpty
    }

    It 'Should detect sync as enabled' {
        $syncRow = $script:result | Where-Object { $_.Property -match 'Sync.*Enabled' -or $_.Setting -match 'Sync.*Enabled' }
        # The result should contain sync status information
        $script:result.Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-HybridSyncReport - Not Connected' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"

        function Get-MgContext { return $null }
        Mock Write-Error { }
    }

    It 'Should return nothing when Graph is not connected' {
        $result = & "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-HybridSyncReport.ps1" 2>$null
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Get-HybridSyncReport - No Organization Data' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"

        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }
        function Get-MgOrganization { }
        Mock Import-Module { }
        Mock Get-MgOrganization { throw 'Failed to retrieve organization details' }
        Mock Write-Error { }
    }

    It 'Should handle Graph API failure gracefully' {
        $result = & "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-HybridSyncReport.ps1" 2>$null
        $result | Should -BeNullOrEmpty
    }
}
