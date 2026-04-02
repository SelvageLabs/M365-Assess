BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-ADDomainReport' {
    BeforeAll {
        # Stub AD cmdlets with parameters before mocking (AD module not installed in CI)
        function Get-ADDomain { }
        function Get-ADForest { }
        function Get-ADReplicationSite {
            param([string]$Filter)
        }
        function Get-ADReplicationSubnet {
            param([string]$Filter)
        }
        function Get-ADTrust {
            param([string]$Filter)
        }
        function Import-Module { }
        # Override Export-Csv to prevent PS7 -Encoding UTF8 binding error
        function Export-Csv { param([string]$Path, [switch]$NoTypeInformation, $Encoding) }

        Mock Import-Module { }
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } }
        Mock Write-Verbose { }
        Mock Write-Warning { }
        Mock Export-Csv { }

        $script:srcPath = "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-ADDomainReport.ps1"
    }

    Context 'when domain and forest data are available' {
        BeforeAll {
            Mock Get-ADDomain {
                return [PSCustomObject]@{
                    DNSRoot              = 'contoso.com'
                    DistinguishedName    = 'DC=contoso,DC=com'
                    NetBIOSName          = 'CONTOSO'
                    DomainMode           = 'Windows2016Domain'
                    PDCEmulator          = 'DC01.contoso.com'
                    RIDMaster            = 'DC01.contoso.com'
                    InfrastructureMaster = 'DC01.contoso.com'
                }
            }

            Mock Get-ADForest {
                return [PSCustomObject]@{
                    Name               = 'contoso.com'
                    RootDomain         = 'contoso.com'
                    ForestMode         = 'Windows2016Forest'
                    SchemaMaster       = 'DC01.contoso.com'
                    DomainNamingMaster = 'DC01.contoso.com'
                    GlobalCatalogs     = @('DC01.contoso.com', 'DC02.contoso.com')
                    Domains            = @('contoso.com')
                    Sites              = @('Default-First-Site-Name')
                }
            }

            Mock Get-ADReplicationSite {
                return @(
                    [PSCustomObject]@{
                        Name              = 'Default-First-Site-Name'
                        DistinguishedName = 'CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
                    }
                )
            }

            Mock Get-ADReplicationSubnet {
                return @(
                    [PSCustomObject]@{ Name = '10.0.0.0/24' }
                )
            }

            Mock Get-ADTrust { return $null }
        }

        It 'should return domain and forest records' {
            $result = & $script:srcPath
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterOrEqual 2
        }

        It 'should include a Domain record with correct DNSRoot' {
            $result = & $script:srcPath
            $domainRecord = $result | Where-Object { $_.RecordType -eq 'Domain' }
            $domainRecord | Should -Not -BeNullOrEmpty
            $domainRecord.Name | Should -Be 'contoso.com'
        }

        It 'should include a Forest record' {
            $result = & $script:srcPath
            $forestRecord = $result | Where-Object { $_.RecordType -eq 'Forest' }
            $forestRecord | Should -Not -BeNullOrEmpty
            $forestRecord.FunctionalLevel | Should -Be 'Windows2016Forest'
        }

        It 'should include a Site record' {
            $result = & $script:srcPath
            $siteRecord = $result | Where-Object { $_.RecordType -eq 'Site' }
            $siteRecord | Should -Not -BeNullOrEmpty
            $siteRecord.Name | Should -Be 'Default-First-Site-Name'
        }

        It 'should include FSMO role holders on domain record' {
            $result = & $script:srcPath
            $domainRecord = $result | Where-Object { $_.RecordType -eq 'Domain' }
            $domainRecord.PDCEmulator | Should -Be 'DC01.contoso.com'
            $domainRecord.RIDMaster | Should -Be 'DC01.contoso.com'
        }
    }

    Context 'when trust relationships exist' {
        BeforeAll {
            Mock Get-ADDomain {
                return [PSCustomObject]@{
                    DNSRoot              = 'contoso.com'
                    DistinguishedName    = 'DC=contoso,DC=com'
                    NetBIOSName          = 'CONTOSO'
                    DomainMode           = 'Windows2016Domain'
                    PDCEmulator          = 'DC01.contoso.com'
                    RIDMaster            = 'DC01.contoso.com'
                    InfrastructureMaster = 'DC01.contoso.com'
                }
            }

            Mock Get-ADForest {
                return [PSCustomObject]@{
                    Name               = 'contoso.com'
                    RootDomain         = 'contoso.com'
                    ForestMode         = 'Windows2016Forest'
                    SchemaMaster       = 'DC01.contoso.com'
                    DomainNamingMaster = 'DC01.contoso.com'
                    GlobalCatalogs     = @('DC01.contoso.com')
                    Domains            = @('contoso.com')
                    Sites              = @('Default-First-Site-Name')
                }
            }

            Mock Get-ADReplicationSite { return @() }
            Mock Get-ADReplicationSubnet { return @() }

            Mock Get-ADTrust {
                return @(
                    [PSCustomObject]@{
                        Name                      = 'partner.com'
                        DistinguishedName         = 'CN=partner.com,CN=System,DC=contoso,DC=com'
                        Direction                 = 3
                        TrustType                 = 2
                        SelectiveAuthentication   = $false
                        ForestTransitive          = $true
                    }
                )
            }
        }

        It 'should include Trust records' {
            $result = & $script:srcPath
            $trustRecord = $result | Where-Object { $_.RecordType -eq 'Trust' }
            $trustRecord | Should -Not -BeNullOrEmpty
            $trustRecord.Name | Should -Be 'partner.com'
        }

        It 'should describe trust direction in Detail' {
            $result = & $script:srcPath
            $trustRecord = $result | Where-Object { $_.RecordType -eq 'Trust' }
            $trustRecord.Detail | Should -Match 'Bidirectional'
        }
    }

    Context 'when Get-ADDomain fails' {
        BeforeAll {
            Mock Get-ADDomain { throw 'Cannot contact domain controller' }
            Mock Write-Error { }
        }

        It 'should return nothing when domain query fails' {
            $result = & $script:srcPath 2>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDomain {
                return [PSCustomObject]@{
                    DNSRoot              = 'contoso.com'
                    DistinguishedName    = 'DC=contoso,DC=com'
                    NetBIOSName          = 'CONTOSO'
                    DomainMode           = 'Windows2016Domain'
                    PDCEmulator          = 'DC01.contoso.com'
                    RIDMaster            = 'DC01.contoso.com'
                    InfrastructureMaster = 'DC01.contoso.com'
                }
            }

            Mock Get-ADForest {
                return [PSCustomObject]@{
                    Name               = 'contoso.com'
                    RootDomain         = 'contoso.com'
                    ForestMode         = 'Windows2016Forest'
                    SchemaMaster       = 'DC01.contoso.com'
                    DomainNamingMaster = 'DC01.contoso.com'
                    GlobalCatalogs     = @('DC01.contoso.com')
                    Domains            = @('contoso.com')
                    Sites              = @('Default-First-Site-Name')
                }
            }

            Mock Get-ADReplicationSite { return @() }
            Mock Get-ADTrust { return $null }
        }

        It 'should export to CSV and return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'domain-report.csv'
            $result = & $script:srcPath -OutputPath $csvPath
            $result | Should -Match 'Exported'
            Should -Invoke Export-Csv -Scope It
        }
    }
}
