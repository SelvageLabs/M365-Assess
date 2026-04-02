BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-StaleComputers' {
    BeforeAll {
        # Stub AD cmdlets as functions before mocking (AD module not installed in CI)
        function Get-ADComputer { }
        function Import-Module { }
        # Override Export-Csv to prevent PS7 -Encoding UTF8 binding error
        function Export-Csv { param([string]$Path, [switch]$NoTypeInformation, $Encoding) }

        Mock Import-Module { }
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } }
        Mock Write-Verbose { }
        Mock Export-Csv { }

        $script:srcPath = "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-StaleComputers.ps1"
    }

    Context 'when stale computers exist' {
        BeforeAll {
            $staleDateFileTime = (Get-Date).AddDays(-120).ToFileTime()
            Mock Get-ADComputer {
                return @(
                    [PSCustomObject]@{
                        Name                   = 'PC-OLD01'
                        Enabled                = $true
                        OperatingSystem        = 'Windows 10 Enterprise'
                        OperatingSystemVersion = '10.0 (19045)'
                        LastLogonTimestamp      = $staleDateFileTime
                        Description            = 'Old workstation'
                        WhenCreated            = (Get-Date).AddYears(-3)
                        DistinguishedName      = 'CN=PC-OLD01,OU=Workstations,DC=contoso,DC=com'
                    },
                    [PSCustomObject]@{
                        Name                   = 'PC-OLD02'
                        Enabled                = $true
                        OperatingSystem        = 'Windows 11 Enterprise'
                        OperatingSystemVersion = '10.0 (22631)'
                        LastLogonTimestamp      = $staleDateFileTime
                        Description            = 'Another old workstation'
                        WhenCreated            = (Get-Date).AddYears(-2)
                        DistinguishedName      = 'CN=PC-OLD02,OU=Workstations,DC=contoso,DC=com'
                    }
                )
            }
        }

        It 'should return stale computer objects' {
            $result = & $script:srcPath -DaysInactive 90
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'should include expected properties on each result' {
            $result = & $script:srcPath -DaysInactive 90
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'DaysSinceLogon'
            $result[0].PSObject.Properties.Name | Should -Contain 'OperatingSystem'
            $result[0].PSObject.Properties.Name | Should -Contain 'LastLogon'
        }

        It 'should invoke Get-ADComputer exactly once' {
            & $script:srcPath -DaysInactive 90 | Out-Null
            Should -Invoke Get-ADComputer -Times 1 -Exactly
        }
    }

    Context 'when no stale computers are found' {
        BeforeAll {
            Mock Get-ADComputer { return @() }
        }

        It 'should return empty results' {
            $result = @(& $script:srcPath -DaysInactive 90)
            # When no computers match, output is empty (no objects)
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when IncludeDisabled is specified' {
        BeforeAll {
            $staleDateFileTime = (Get-Date).AddDays(-100).ToFileTime()
            Mock Get-ADComputer {
                return @(
                    [PSCustomObject]@{
                        Name                   = 'PC-DISABLED'
                        Enabled                = $false
                        OperatingSystem        = 'Windows 10 Enterprise'
                        OperatingSystemVersion = '10.0 (19045)'
                        LastLogonTimestamp      = $staleDateFileTime
                        Description            = 'Disabled workstation'
                        WhenCreated            = (Get-Date).AddYears(-1)
                        DistinguishedName      = 'CN=PC-DISABLED,OU=Disabled,DC=contoso,DC=com'
                    },
                    [PSCustomObject]@{
                        Name                   = 'PC-ENABLED'
                        Enabled                = $true
                        OperatingSystem        = 'Windows 10 Enterprise'
                        OperatingSystemVersion = '10.0 (19045)'
                        LastLogonTimestamp      = $staleDateFileTime
                        Description            = 'Enabled workstation'
                        WhenCreated            = (Get-Date).AddYears(-1)
                        DistinguishedName      = 'CN=PC-ENABLED,OU=Workstations,DC=contoso,DC=com'
                    }
                )
            }
        }

        It 'should include disabled computers when -IncludeDisabled is set' {
            $result = & $script:srcPath -DaysInactive 90 -IncludeDisabled
            $result.Count | Should -Be 2
        }

        It 'should exclude disabled computers by default' {
            $result = & $script:srcPath -DaysInactive 90
            @($result).Count | Should -Be 1
            $result[0].Name | Should -Be 'PC-ENABLED'
        }
    }

    Context 'when a computer has never logged on' {
        BeforeAll {
            Mock Get-ADComputer {
                return @(
                    [PSCustomObject]@{
                        Name                   = 'PC-NEVERLOGON'
                        Enabled                = $true
                        OperatingSystem        = 'Windows 10 Enterprise'
                        OperatingSystemVersion = '10.0 (19045)'
                        LastLogonTimestamp      = $null
                        Description            = 'Never logged on'
                        WhenCreated            = (Get-Date).AddDays(-5)
                        DistinguishedName      = 'CN=PC-NEVERLOGON,OU=Workstations,DC=contoso,DC=com'
                    }
                )
            }
        }

        It 'should report DaysSinceLogon as Never' {
            $result = & $script:srcPath -DaysInactive 90
            $result[0].DaysSinceLogon | Should -Be 'Never'
        }

        It 'should have null LastLogon' {
            $result = & $script:srcPath -DaysInactive 90
            $result[0].LastLogon | Should -BeNullOrEmpty
        }
    }

    Context 'when AD query fails' {
        BeforeAll {
            Mock Get-ADComputer { throw 'Access denied' }
            Mock Write-Error { }
        }

        It 'should handle the error gracefully' {
            $result = & $script:srcPath -DaysInactive 90 2>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $staleDateFileTime = (Get-Date).AddDays(-120).ToFileTime()
            Mock Get-ADComputer {
                return @(
                    [PSCustomObject]@{
                        Name                   = 'PC-EXPORT'
                        Enabled                = $true
                        OperatingSystem        = 'Windows 10 Enterprise'
                        OperatingSystemVersion = '10.0 (19045)'
                        LastLogonTimestamp      = $staleDateFileTime
                        Description            = 'Export test'
                        WhenCreated            = (Get-Date).AddYears(-1)
                        DistinguishedName      = 'CN=PC-EXPORT,OU=Workstations,DC=contoso,DC=com'
                    }
                )
            }
        }

        It 'should export to CSV and return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'stale.csv'
            $result = & $script:srcPath -DaysInactive 90 -OutputPath $csvPath
            $result | Should -Match 'Exported'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }
}
