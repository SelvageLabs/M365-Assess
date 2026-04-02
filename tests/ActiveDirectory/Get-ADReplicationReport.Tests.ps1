BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-ADReplicationReport' {
    BeforeAll {
        # Stub AD cmdlets with parameters before mocking (AD module not installed in CI)
        function Get-ADDomainController {
            param([string]$Filter, [string]$Identity)
        }
        function Get-ADReplicationPartnerMetadata {
            param([string]$Target)
        }
        function Get-ADReplicationFailure {
            param([string]$Target)
        }
        function Get-ADReplicationSiteLink {
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

        $script:srcPath = "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-ADReplicationReport.ps1"

        $script:mockDC = [PSCustomObject]@{
            HostName = 'DC01.contoso.com'
        }
    }

    Context 'when replication is healthy' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @($script:mockDC)
            }

            $now = Get-Date
            Mock Get-ADReplicationPartnerMetadata {
                return @(
                    [PSCustomObject]@{
                        Partner                        = 'CN=NTDS Settings,CN=DC02,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
                        PartnerType                    = 'Inbound'
                        LastReplicationAttempt          = $now
                        LastReplicationSuccess          = $now
                        LastReplicationResult           = 0
                        ConsecutiveReplicationFailures  = 0
                    }
                )
            }

            Mock Get-ADReplicationFailure { return @() }

            Mock Get-ADReplicationSiteLink {
                return @(
                    [PSCustomObject]@{
                        Name                          = 'DEFAULTIPSITELINK'
                        SitesIncluded                 = @('CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com')
                        Cost                          = 100
                        ReplicationFrequencyInMinutes = 180
                    }
                )
            }

            $script:result = & $script:srcPath
        }

        It 'should return replication records' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'should include a healthy ReplicationPartner record' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord | Should -Not -BeNullOrEmpty
            $partnerRecord.ReplicationStatus | Should -Be 'Healthy'
        }

        It 'should include a SiteLink record' {
            $siteLink = $script:result | Where-Object { $_.RecordType -eq 'SiteLink' }
            $siteLink | Should -Not -BeNullOrEmpty
            $siteLink.Partner | Should -Be 'DEFAULTIPSITELINK'
        }

        It 'should have zero consecutive failures for healthy partner' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord.ConsecutiveFailures | Should -Be 0
        }
    }

    Context 'when replication has warnings (1-3 failures)' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @($script:mockDC)
            }

            $now = Get-Date
            Mock Get-ADReplicationPartnerMetadata {
                return @(
                    [PSCustomObject]@{
                        Partner                        = 'CN=NTDS Settings,CN=DC02,CN=Servers'
                        PartnerType                    = 'Inbound'
                        LastReplicationAttempt          = $now
                        LastReplicationSuccess          = $now.AddMinutes(-10)
                        LastReplicationResult           = 1
                        ConsecutiveReplicationFailures  = 2
                    }
                )
            }

            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }

            $script:result = & $script:srcPath
        }

        It 'should mark replication status as Warning' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord.ReplicationStatus | Should -Be 'Warning'
        }

        It 'should include consecutive failure count in Detail' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord.Detail | Should -Match 'ConsecutiveFailures=2'
        }
    }

    Context 'when replication has errors (lag > 24h)' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @($script:mockDC)
            }

            $now = Get-Date
            Mock Get-ADReplicationPartnerMetadata {
                return @(
                    [PSCustomObject]@{
                        Partner                        = 'CN=NTDS Settings,CN=DC02,CN=Servers'
                        PartnerType                    = 'Inbound'
                        LastReplicationAttempt          = $now
                        LastReplicationSuccess          = $now.AddHours(-30)
                        LastReplicationResult           = 0
                        ConsecutiveReplicationFailures  = 0
                    }
                )
            }

            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }

            $script:result = & $script:srcPath
        }

        It 'should mark replication status as Error for large lag' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord.ReplicationStatus | Should -Be 'Error'
        }

        It 'should include replication lag in Detail' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord.Detail | Should -Match 'ReplicationLag='
        }
    }

    Context 'when no replication partners exist' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @($script:mockDC)
            }

            Mock Get-ADReplicationPartnerMetadata { return @() }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }

            $script:result = & $script:srcPath
        }

        It 'should return a No Partners record' {
            $partnerRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationPartner' }
            $partnerRecord | Should -Not -BeNullOrEmpty
            $partnerRecord.ReplicationStatus | Should -Be 'No Partners'
        }
    }

    Context 'when replication failure history exists' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @($script:mockDC)
            }

            $now = Get-Date
            Mock Get-ADReplicationPartnerMetadata {
                return @(
                    [PSCustomObject]@{
                        Partner                        = 'CN=NTDS Settings,CN=DC02,CN=Servers'
                        PartnerType                    = 'Inbound'
                        LastReplicationAttempt          = $now
                        LastReplicationSuccess          = $now
                        LastReplicationResult           = 0
                        ConsecutiveReplicationFailures  = 0
                    }
                )
            }

            Mock Get-ADReplicationFailure {
                return @(
                    [PSCustomObject]@{
                        Partner          = 'DC02.contoso.com'
                        FirstFailureTime = $now.AddHours(-5)
                        LastError        = 8456
                        FailureCount     = 3
                        FailureType      = 'KCC'
                    }
                )
            }

            Mock Get-ADReplicationSiteLink { return @() }

            $script:result = & $script:srcPath
        }

        It 'should include ReplicationFailure records' {
            $failureRecord = $script:result | Where-Object { $_.RecordType -eq 'ReplicationFailure' }
            $failureRecord | Should -Not -BeNullOrEmpty
            $failureRecord.ReplicationStatus | Should -Be 'FailureRecord'
        }
    }

    Context 'when no domain controllers are found' {
        BeforeAll {
            Mock Get-ADDomainController { return @() }
            Mock Write-Error { }
        }

        It 'should return nothing' {
            $result = & $script:srcPath 2>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @($script:mockDC)
            }

            Mock Get-ADReplicationPartnerMetadata { return @() }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should export to CSV and return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'replication.csv'
            $result = & $script:srcPath -OutputPath $csvPath
            $result | Should -Match 'Exported'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }
}
