BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-ADDCHealthReport' {
    BeforeAll {
        # Stub AD cmdlets with parameters before mocking (AD module not installed in CI)
        function Get-ADDomainController {
            param([string]$Filter, [string]$Identity)
        }
        function Import-Module { }
        # Override Export-Csv to prevent PS7 -Encoding UTF8 binding error
        function Export-Csv { param([string]$Path, [switch]$NoTypeInformation, $Encoding) }

        Mock Import-Module { }
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } }
        Mock Write-Verbose { }
        Mock Write-Warning { }
        Mock Export-Csv { }

        $script:srcPath = "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-ADDCHealthReport.ps1"

        # Default DC object used across contexts
        $script:mockDC = [PSCustomObject]@{
            HostName             = 'DC01.contoso.com'
            Site                 = 'Default-First-Site-Name'
            IPv4Address          = '10.0.0.1'
            OperatingSystem      = 'Windows Server 2022 Datacenter'
            IsGlobalCatalog      = $true
            IsReadOnly           = $false
            OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
        }
    }

    Context 'when SkipDcdiag is specified' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName             = 'DC01.contoso.com'
                    Site                 = 'Default-First-Site-Name'
                    IPv4Address          = '10.0.0.1'
                    OperatingSystem      = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog      = $true
                    IsReadOnly           = $false
                    OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                })
            }

            $script:result = & $script:srcPath -SkipDcdiag
        }

        It 'should return DC inventory results' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'should mark dcdiag as Skipped' {
            $script:result[0].DcdiagResult | Should -Be 'Skipped'
        }

        It 'should include DC hostname' {
            $script:result[0].DomainController | Should -Be 'DC01.contoso.com'
        }

        It 'should include FSMO roles' {
            $script:result[0].FSMORoles | Should -Match 'PDCEmulator'
        }

        It 'should include site information' {
            $script:result[0].Site | Should -Be 'Default-First-Site-Name'
        }

        It 'should include global catalog flag' {
            $script:result[0].IsGlobalCatalog | Should -BeTrue
        }
    }

    Context 'when dcdiag returns passing tests' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName             = 'DC01.contoso.com'
                    Site                 = 'Default-First-Site-Name'
                    IPv4Address          = '10.0.0.1'
                    OperatingSystem      = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog      = $true
                    IsReadOnly           = $false
                    OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                })
            }

            # Pre-define the Invoke-Dcdiag function so the script will not define its own
            function Invoke-Dcdiag { }
            Mock Invoke-Dcdiag {
                return @(
                    '         ......................... DC01 passed test Connectivity'
                    '         ......................... DC01 passed test Advertising'
                    '         ......................... DC01 passed test Services'
                )
            }

            $script:result = & $script:srcPath
        }

        It 'should return one row per parsed test' {
            $script:result.Count | Should -Be 3
        }

        It 'should mark all tests as Passed' {
            $script:result | ForEach-Object {
                $_.DcdiagResult | Should -Be 'Passed'
            }
        }

        It 'should include test names' {
            $testNames = $script:result | ForEach-Object { $_.DcdiagTest }
            $testNames | Should -Contain 'Connectivity'
            $testNames | Should -Contain 'Advertising'
        }
    }

    Context 'when dcdiag returns failed tests' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName             = 'DC01.contoso.com'
                    Site                 = 'Default-First-Site-Name'
                    IPv4Address          = '10.0.0.1'
                    OperatingSystem      = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog      = $true
                    IsReadOnly           = $false
                    OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                })
            }

            function Invoke-Dcdiag { }
            Mock Invoke-Dcdiag {
                return @(
                    '         ......................... DC01 passed test Connectivity'
                    '         ......................... DC01 failed test Services'
                )
            }

            $script:result = & $script:srcPath
        }

        It 'should mark failed test as Failed' {
            $failedRow = $script:result | Where-Object { $_.DcdiagTest -eq 'Services' }
            $failedRow.DcdiagResult | Should -Be 'Failed'
        }

        It 'should include failure details' {
            $failedRow = $script:result | Where-Object { $_.DcdiagTest -eq 'Services' }
            $failedRow.DcdiagDetails | Should -Match 'failed'
        }
    }

    Context 'when Invoke-Dcdiag throws' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName             = 'DC01.contoso.com'
                    Site                 = 'Default-First-Site-Name'
                    IPv4Address          = '10.0.0.1'
                    OperatingSystem      = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog      = $true
                    IsReadOnly           = $false
                    OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                })
            }

            function Invoke-Dcdiag { }
            Mock Invoke-Dcdiag { throw 'dcdiag.exe is not available' }

            $script:result = & $script:srcPath
        }

        It 'should return a Skipped result row' {
            $script:result | Should -Not -BeNullOrEmpty
            $script:result[0].DcdiagResult | Should -Be 'Skipped'
        }

        It 'should include unavailability detail' {
            $script:result[0].DcdiagDetails | Should -Match 'unavailable'
        }
    }

    Context 'when no domain controllers are found' {
        BeforeAll {
            Mock Get-ADDomainController { return @() }
            Mock Write-Error { }
        }

        It 'should return nothing' {
            $result = & $script:srcPath -SkipDcdiag 2>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when specific DCs are requested' {
        BeforeAll {
            Mock Get-ADDomainController {
                return [PSCustomObject]@{
                    HostName             = 'DC01.contoso.com'
                    Site                 = 'Default-First-Site-Name'
                    IPv4Address          = '10.0.0.1'
                    OperatingSystem      = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog      = $true
                    IsReadOnly           = $false
                    OperationMasterRoles = @('PDCEmulator')
                }
            }

            function Invoke-Dcdiag { }
            Mock Invoke-Dcdiag {
                return @(
                    '         ......................... DC01 passed test Connectivity'
                )
            }
        }

        It 'should query the specified DC and return results' {
            $result = & $script:srcPath -DomainController 'DC01.contoso.com'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName             = 'DC01.contoso.com'
                    Site                 = 'Default-First-Site-Name'
                    IPv4Address          = '10.0.0.1'
                    OperatingSystem      = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog      = $true
                    IsReadOnly           = $false
                    OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                })
            }
        }

        It 'should export to CSV and return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'dc-health.csv'
            $result = & $script:srcPath -SkipDcdiag -OutputPath $csvPath
            $result | Should -Match 'Exported'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }
}
