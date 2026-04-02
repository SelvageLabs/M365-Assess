BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Resolve-M365Environment' {
    BeforeAll {
        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/Resolve-M365Environment.ps1"
    }

    Context 'when tenant is Commercial' {
        BeforeAll {
            Mock Invoke-RestMethod {
                return @{
                    tenant_region_scope    = 'NA'
                    tenant_region_sub_scope = $null
                }
            }
        }

        It 'should return commercial' {
            $result = Resolve-M365Environment -TenantId 'contoso.onmicrosoft.com'
            $result | Should -Be 'commercial'
        }

        It 'should call the commercial authority first' {
            Resolve-M365Environment -TenantId 'contoso.onmicrosoft.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*login.microsoftonline.com*'
            }
        }
    }

    Context 'when tenant is GCC' {
        BeforeAll {
            Mock Invoke-RestMethod {
                return @{
                    tenant_region_scope    = 'NA'
                    tenant_region_sub_scope = 'GCC'
                }
            }
        }

        It 'should return gcc' {
            $result = Resolve-M365Environment -TenantId 'gcc-tenant.onmicrosoft.com'
            $result | Should -Be 'gcc'
        }
    }

    Context 'when tenant is GCC High (found on .us authority)' {
        BeforeAll {
            # Commercial authority fails, .us authority succeeds
            Mock Invoke-RestMethod { throw 'Not found' } -ParameterFilter {
                $Uri -like '*login.microsoftonline.com*'
            }
            Mock Invoke-RestMethod {
                return @{
                    tenant_region_scope    = 'USGov'
                    tenant_region_sub_scope = $null
                }
            } -ParameterFilter {
                $Uri -like '*login.microsoftonline.us*'
            }
        }

        It 'should return gcchigh' {
            $result = Resolve-M365Environment -TenantId 'gcchigh-tenant.onmicrosoft.us'
            $result | Should -Be 'gcchigh'
        }

        It 'should try commercial first then fall back to .us' {
            Resolve-M365Environment -TenantId 'gcchigh-tenant.onmicrosoft.us'
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        }
    }

    Context 'when tenant is GCC High (found on commercial authority with legacy .com domain)' {
        BeforeAll {
            Mock Invoke-RestMethod {
                return @{
                    tenant_region_scope    = 'USGov'
                    tenant_region_sub_scope = $null
                }
            }
        }

        It 'should return gcchigh' {
            $result = Resolve-M365Environment -TenantId 'legacy-gcchigh.onmicrosoft.com'
            $result | Should -Be 'gcchigh'
        }
    }

    Context 'when both authorities fail' {
        BeforeAll {
            Mock Invoke-RestMethod { throw 'Not found' }
        }

        It 'should return null' {
            $result = Resolve-M365Environment -TenantId 'nonexistent.onmicrosoft.com'
            $result | Should -BeNullOrEmpty
        }

        It 'should try both authorities' {
            Resolve-M365Environment -TenantId 'nonexistent.onmicrosoft.com'
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        }
    }
}
