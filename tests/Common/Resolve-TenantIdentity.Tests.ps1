BeforeAll {
    . "$PSScriptRoot/../../src/M365-Assess/Common/Resolve-TenantIdentity.ps1"
}

Describe 'Resolve-TenantIdentity (C1 #780)' {
    Context 'when Get-MgContext returns a TenantId' {
        BeforeAll {
            Mock Get-MgContext { return [pscustomobject]@{ TenantId = '11111111-2222-3333-4444-555555555555' } }
            Mock Get-MgOrganization {
                return [pscustomobject]@{
                    DisplayName     = 'Contoso Ltd'
                    VerifiedDomains = @(
                        [pscustomobject]@{ Name = 'contoso.onmicrosoft.com'; IsDefault = $false }
                        [pscustomobject]@{ Name = 'contoso.com';             IsDefault = $true }
                    )
                }
            }
        }

        It 'should return Source = Graph' {
            $r = Resolve-TenantIdentity -TenantIdInput 'contoso.com' -Environment 'commercial'
            $r.Source | Should -Be 'Graph'
        }

        It 'should return the GUID from Get-MgContext' {
            $r = Resolve-TenantIdentity -TenantIdInput 'contoso.com'
            $r.Guid | Should -Be '11111111-2222-3333-4444-555555555555'
        }

        It 'should populate DisplayName from Get-MgOrganization' {
            $r = Resolve-TenantIdentity -TenantIdInput 'contoso.com'
            $r.DisplayName | Should -Be 'Contoso Ltd'
        }

        It 'should populate PrimaryDomain from the IsDefault verified domain' {
            $r = Resolve-TenantIdentity -TenantIdInput 'contoso.com'
            $r.PrimaryDomain | Should -Be 'contoso.com'
        }

        It 'should preserve the user-supplied TenantInput verbatim' {
            $r = Resolve-TenantIdentity -TenantIdInput 'contoso.com'
            $r.TenantInput | Should -Be 'contoso.com'
        }
    }

    Context 'when Get-MgContext returns null (Graph not connected)' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should return Source = Fallback' {
            $r = Resolve-TenantIdentity -TenantIdInput 'fallback.tenant.com'
            $r.Source | Should -Be 'Fallback'
        }

        It 'should derive a deterministic GUID-shaped key from the TenantIdInput' {
            $r1 = Resolve-TenantIdentity -TenantIdInput 'fallback.tenant.com'
            $r2 = Resolve-TenantIdentity -TenantIdInput 'fallback.tenant.com'
            $r1.Guid | Should -Be $r2.Guid
            $r1.Guid | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }

        It 'should produce different keys for different TenantIdInput values' {
            $a = Resolve-TenantIdentity -TenantIdInput 'tenantA.onmicrosoft.com'
            $b = Resolve-TenantIdentity -TenantIdInput 'tenantB.onmicrosoft.com'
            $a.Guid | Should -Not -Be $b.Guid
        }

        It 'should be case-insensitive on the TenantIdInput hash' {
            $upper = Resolve-TenantIdentity -TenantIdInput 'CONTOSO.COM'
            $lower = Resolve-TenantIdentity -TenantIdInput 'contoso.com'
            $upper.Guid | Should -Be $lower.Guid
        }
    }

    Context 'Environment metadata passthrough' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should record the supplied Environment value' {
            $r = Resolve-TenantIdentity -TenantIdInput 'gov.onmicrosoft.us' -Environment 'gcchigh'
            $r.Environment | Should -Be 'gcchigh'
        }
    }
}

Describe 'Resolve-BaselineFolder (C1 #780)' {
    Context 'when both GUID and TenantId are supplied' {
        It 'should prefer the GUID path when it exists' {
            $output = $TestDrive
            $guidFolder   = Join-Path $output 'Baselines\Q1_11111111-2222-3333-4444-555555555555'
            $legacyFolder = Join-Path $output 'Baselines\Q1_contoso.com'
            $null = New-Item $guidFolder   -ItemType Directory -Force
            $null = New-Item $legacyFolder -ItemType Directory -Force
            $resolved = Resolve-BaselineFolder -OutputFolder $output -Label 'Q1' -TenantGuid '11111111-2222-3333-4444-555555555555' -TenantId 'contoso.com'
            $resolved | Should -Be $guidFolder
        }

        It 'should fall back to the legacy TenantId path when only legacy exists' {
            $output = Join-Path $TestDrive 'fb1'
            $legacyFolder = Join-Path $output 'Baselines\Q1_legacytenant.com'
            $null = New-Item $legacyFolder -ItemType Directory -Force
            $resolved = Resolve-BaselineFolder -OutputFolder $output -Label 'Q1' -TenantGuid '11111111-2222-3333-4444-555555555555' -TenantId 'legacytenant.com'
            $resolved | Should -Be $legacyFolder
        }

        It 'should return the canonical (GUID) path when neither exists' {
            $output = Join-Path $TestDrive 'fb2'
            $resolved = Resolve-BaselineFolder -OutputFolder $output -Label 'Q1' -TenantGuid '11111111-2222-3333-4444-555555555555' -TenantId 'contoso.com'
            $resolved | Should -Match '_11111111-2222-3333-4444-555555555555$'
        }
    }
}
