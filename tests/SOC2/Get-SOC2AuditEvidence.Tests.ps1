BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-SOC2AuditEvidence' {
    BeforeAll {
        function Invoke-MgGraphRequest { param($Method, $Uri, $ErrorAction) }
        function Get-MgContext { }

        Mock Get-MgContext {
            return [PSCustomObject]@{ TenantId = 'test-tenant-id'; Account = 'admin@contoso.com' }
        }

        . "$PSScriptRoot/../../src/M365-Assess/Orchestrator/AssessmentHelpers.ps1"
    }

    Context 'when audit logs return data' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                if ($Uri -match 'auditLogs/signIns.*status/errorCode ne 0') {
                    return @{ value = @(
                        @{ createdDateTime = '2026-03-15T10:00:00Z'; userDisplayName = 'User1'; status = @{ errorCode = 50126 } }
                        @{ createdDateTime = '2026-03-16T10:00:00Z'; userDisplayName = 'User2'; status = @{ errorCode = 50126 } }
                    ) }
                }
                if ($Uri -match 'identityProtection/riskDetections') {
                    return @{ value = @(
                        @{ detectedDateTime = '2026-03-15T10:00:00Z'; riskEventType = 'anonymizedIPAddress'; riskLevel = 'medium' }
                    ) }
                }
                if ($Uri -match 'security/alerts_v2') {
                    return @{ value = @(
                        @{ createdDateTime = '2026-03-15T10:00:00Z'; title = 'Test Alert'; status = 'resolved' }
                    ) }
                }
                if ($Uri -match 'auditLogs/directoryAudits') {
                    return @{ value = @(
                        @{ activityDateTime = '2026-03-15T10:00:00Z'; activityDisplayName = 'Add member to role'; targetResources = @(@{ displayName = 'Global Admin' }) }
                    ) }
                }
                return @{ value = @() }
            }

            $result = & "$PSScriptRoot/../../src/M365-Assess/SOC2/Get-SOC2AuditEvidence.ps1"
        }

        It 'should return evidence records' {
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should include expected properties' {
            $first = $result | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain 'EvidenceType'
            $first.PSObject.Properties.Name | Should -Contain 'EventCount'
            $first.PSObject.Properties.Name | Should -Contain 'TrustPrinciple'
        }

        It 'should include sign-in related evidence' {
            $signInEvidence = $result | Where-Object { $_.EvidenceType -match 'Sign-In|SignIn|sign' }
            $signInEvidence | Should -Not -BeNullOrEmpty
        }

        It 'should include risk or alert evidence' {
            $riskEvidence = $result | Where-Object { $_.EvidenceType -match 'Risk|Alert|Incident' }
            $riskEvidence | Should -Not -BeNullOrEmpty
        }

        It 'should have multiple evidence categories' {
            @($result).Count | Should -BeGreaterOrEqual 3
        }
    }

    Context 'when audit logs are empty' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                return @{ value = @() }
            }

            $result = & "$PSScriptRoot/../../src/M365-Assess/SOC2/Get-SOC2AuditEvidence.ps1"
        }

        It 'should still return evidence records with zero counts' {
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should show 0 event counts' {
            $zeroEvents = $result | Where-Object { $_.EventCount -eq 0 }
            $zeroEvents | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when Graph connection is not established' {
        BeforeAll {
            Mock Get-MgContext { return $null }
            # Script sets ErrorActionPreference=Stop internally, so Write-Error terminates.
            # Wrap in try/catch to capture the early-exit behavior.
            $result = try { & "$PSScriptRoot/../../src/M365-Assess/SOC2/Get-SOC2AuditEvidence.ps1" 2>$null } catch { $null }
        }

        It 'should return nothing' {
            $result | Should -BeNullOrEmpty
        }
    }
}
