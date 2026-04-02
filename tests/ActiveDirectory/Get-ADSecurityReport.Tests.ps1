BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-ADSecurityReport' {
    BeforeAll {
        # Stub AD cmdlets with parameters before mocking (AD module not installed in CI)
        function Get-ADDefaultDomainPasswordPolicy { }
        function Get-ADFineGrainedPasswordPolicy {
            param([string]$Filter)
        }
        function Get-ADGroupMember {
            param([string]$Identity)
        }
        function Get-ADUser {
            param([scriptblock]$Filter, [string[]]$Properties)
        }
        function Import-Module { }
        # Override Export-Csv to prevent PS7 -Encoding UTF8 binding error
        function Export-Csv { param([string]$Path, [switch]$NoTypeInformation, $Encoding) }

        Mock Import-Module { }
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } }
        Mock Write-Verbose { }
        Mock Write-Warning { }
        Mock Export-Csv { }

        $script:srcPath = "$PSScriptRoot/../../src/M365-Assess/ActiveDirectory/Get-ADSecurityReport.ps1"
    }

    Context 'when strong password policy is configured' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = (New-TimeSpan -Days 90)
                    MinPasswordAge               = (New-TimeSpan -Days 1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled            = $true
                    ReversibleEncryptionEnabled  = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = (New-TimeSpan -Minutes 30)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 30)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }

            $script:result = & $script:srcPath
        }

        It 'should return password policy records' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'should include the default domain password policy as Info' {
            $policyRecord = $script:result | Where-Object {
                $_.RecordType -eq 'PasswordPolicy' -and $_.Name -eq 'Default Domain Password Policy'
            }
            $policyRecord | Should -Not -BeNullOrEmpty
            $policyRecord.RiskLevel | Should -Be 'Info'
        }

        It 'should NOT flag weak password length when >= 8' {
            $weakRecord = $script:result | Where-Object { $_.Name -eq 'Weak minimum password length' }
            $weakRecord | Should -BeNullOrEmpty
        }

        It 'should NOT flag complexity when enabled' {
            $complexityRecord = $script:result | Where-Object { $_.Name -eq 'Password complexity disabled' }
            $complexityRecord | Should -BeNullOrEmpty
        }
    }

    Context 'when weak password policy is configured' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 4
                    MaxPasswordAge               = (New-TimeSpan -Days 0)
                    MinPasswordAge               = (New-TimeSpan -Days 0)
                    PasswordHistoryCount         = 0
                    ComplexityEnabled            = $false
                    ReversibleEncryptionEnabled  = $true
                    LockoutThreshold             = 0
                    LockoutDuration              = (New-TimeSpan -Minutes 0)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 0)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }

            $script:result = & $script:srcPath
        }

        It 'should flag weak minimum password length as High' {
            $weakRecord = $script:result | Where-Object { $_.Name -eq 'Weak minimum password length' }
            $weakRecord | Should -Not -BeNullOrEmpty
            $weakRecord.RiskLevel | Should -Be 'High'
        }

        It 'should flag disabled complexity as High' {
            $complexityRecord = $script:result | Where-Object { $_.Name -eq 'Password complexity disabled' }
            $complexityRecord | Should -Not -BeNullOrEmpty
            $complexityRecord.RiskLevel | Should -Be 'High'
        }

        It 'should flag no account lockout as High' {
            $lockoutRecord = $script:result | Where-Object { $_.Name -eq 'No account lockout configured' }
            $lockoutRecord | Should -Not -BeNullOrEmpty
            $lockoutRecord.RiskLevel | Should -Be 'High'
        }

        It 'should flag reversible encryption as Critical' {
            $reversibleRecord = $script:result | Where-Object { $_.Name -eq 'Reversible encryption enabled' }
            $reversibleRecord | Should -Not -BeNullOrEmpty
            $reversibleRecord.RiskLevel | Should -Be 'Critical'
        }
    }

    Context 'when fine-grained password policies exist' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = (New-TimeSpan -Days 90)
                    MinPasswordAge               = (New-TimeSpan -Days 1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled            = $true
                    ReversibleEncryptionEnabled  = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = (New-TimeSpan -Minutes 30)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 30)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy {
                return @(
                    [PSCustomObject]@{
                        Name                 = 'ServiceAccounts-PSO'
                        Precedence           = 10
                        MinPasswordLength    = 20
                        MaxPasswordAge       = (New-TimeSpan -Days 0)
                        PasswordHistoryCount = 24
                        ComplexityEnabled    = $true
                        LockoutThreshold     = 0
                        AppliesTo            = @('CN=ServiceAccounts,OU=Groups,DC=contoso,DC=com')
                    }
                )
            }

            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }

            $script:result = & $script:srcPath
        }

        It 'should include fine-grained policy records' {
            $fgpRecord = $script:result | Where-Object {
                $_.RecordType -eq 'PasswordPolicy' -and $_.Category -eq 'Fine-Grained Policy'
            }
            $fgpRecord | Should -Not -BeNullOrEmpty
            $fgpRecord.Name | Should -Be 'ServiceAccounts-PSO'
        }
    }

    Context 'when privileged groups have members' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = (New-TimeSpan -Days 90)
                    MinPasswordAge               = (New-TimeSpan -Days 1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled            = $true
                    ReversibleEncryptionEnabled  = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = (New-TimeSpan -Minutes 30)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 30)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy { return @() }

            Mock Get-ADGroupMember {
                return @(
                    [PSCustomObject]@{ SamAccountName = 'admin1' },
                    [PSCustomObject]@{ SamAccountName = 'admin2' }
                )
            }

            Mock Get-ADUser { return @() }

            $script:result = & $script:srcPath
        }

        It 'should include PrivilegedGroup records' {
            $groupRecords = $script:result | Where-Object { $_.RecordType -eq 'PrivilegedGroup' }
            $groupRecords | Should -Not -BeNullOrEmpty
        }

        It 'should report member count in Value' {
            $groupRecord = $script:result | Where-Object {
                $_.RecordType -eq 'PrivilegedGroup' -and $_.Name -eq 'Domain Admins'
            }
            $groupRecord.Value | Should -Be '2 members'
        }

        It 'should list member names in Detail' {
            $groupRecord = $script:result | Where-Object {
                $_.RecordType -eq 'PrivilegedGroup' -and $_.Name -eq 'Domain Admins'
            }
            $groupRecord.Detail | Should -Match 'admin1'
            $groupRecord.Detail | Should -Match 'admin2'
        }
    }

    Context 'when flagged user accounts exist' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = (New-TimeSpan -Days 90)
                    MinPasswordAge               = (New-TimeSpan -Days 1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled            = $true
                    ReversibleEncryptionEnabled  = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = (New-TimeSpan -Minutes 30)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 30)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }

            # Single mock for Get-ADUser that returns different data based on the call
            # The script calls Get-ADUser three times with different -Filter scriptblocks.
            # Since we cannot reliably match scriptblock Filter content in parameter filters,
            # we use a counter to return different data for each successive call.
            $script:adUserCallCount = 0
            Mock Get-ADUser {
                $script:adUserCallCount++
                switch ($script:adUserCallCount) {
                    1 {
                        # PasswordNeverExpires query
                        return @([PSCustomObject]@{ SamAccountName = 'svc-neverexpire' })
                    }
                    2 {
                        # PasswordNotRequired query
                        return @([PSCustomObject]@{ SamAccountName = 'svc-nopw' })
                    }
                    3 {
                        # AllowReversiblePasswordEncryption query
                        return @([PSCustomObject]@{ SamAccountName = 'svc-reversible' })
                    }
                    default { return @() }
                }
            }

            $script:result = & $script:srcPath
        }

        It 'should flag PasswordNeverExpires accounts' {
            $neverExpires = $script:result | Where-Object {
                $_.RecordType -eq 'FlaggedAccounts' -and $_.Category -eq 'Password Never Expires'
            }
            $neverExpires | Should -Not -BeNullOrEmpty
            $neverExpires.Detail | Should -Match 'svc-neverexpire'
        }

        It 'should flag PasswordNotRequired accounts as Critical' {
            $noPassword = $script:result | Where-Object {
                $_.RecordType -eq 'FlaggedAccounts' -and $_.Category -eq 'Password Not Required'
            }
            $noPassword | Should -Not -BeNullOrEmpty
            $noPassword.RiskLevel | Should -Be 'Critical'
        }

        It 'should flag reversible encryption accounts as Critical' {
            $reversible = $script:result | Where-Object {
                $_.RecordType -eq 'FlaggedAccounts' -and $_.Category -eq 'Reversible Encryption'
            }
            $reversible | Should -Not -BeNullOrEmpty
            $reversible.RiskLevel | Should -Be 'Critical'
        }
    }

    Context 'when no flagged accounts exist' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = (New-TimeSpan -Days 90)
                    MinPasswordAge               = (New-TimeSpan -Days 1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled            = $true
                    ReversibleEncryptionEnabled  = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = (New-TimeSpan -Minutes 30)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 30)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }

            $script:result = & $script:srcPath
        }

        It 'should not include any FlaggedAccounts records' {
            $flagged = $script:result | Where-Object { $_.RecordType -eq 'FlaggedAccounts' }
            $flagged | Should -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = (New-TimeSpan -Days 90)
                    MinPasswordAge               = (New-TimeSpan -Days 1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled            = $true
                    ReversibleEncryptionEnabled  = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = (New-TimeSpan -Minutes 30)
                    LockoutObservationWindow     = (New-TimeSpan -Minutes 30)
                }
            }

            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }
        }

        It 'should export to CSV and return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'security.csv'
            $result = & $script:srcPath -OutputPath $csvPath
            $result | Should -Match 'Exported'
            Should -Invoke Export-Csv -Scope It
        }
    }
}
