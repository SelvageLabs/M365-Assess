# v0.8.4 Hardening & Housekeeping Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.8.4 with bug fixes, expanded Pester coverage for all 9 security collectors, updated testing policy, org attribution, and consolidated CHANGELOG entries for all work since v0.8.1.

**Architecture:** Six independent work streams (bugs, CLAUDE.md, tests, org attribution, CHANGELOG, version bump) with only the version bump depending on all others completing first. Test expansion follows the established pattern in `tests/Entra/Get-EntraSecurityConfig.Tests.ps1`: mock all external cmdlets in BeforeAll, dot-source the collector, then assert on `$settings` output.

**Tech Stack:** PowerShell 7.x, Pester 5.x, PSScriptAnalyzer, GitHub CLI

**Branch:** `chore/org-attribution` (already in progress, will carry all v0.8.4 work)

**Issues:** #88, #89, #90, #91, #93, #94

---

## Chunk 1: Quick Fixes and Policy Updates

### Task 1: Fix unsafe array access in Get-EntraSecurityConfig.ps1 (#88)

**Files:**
- Modify: `Entra/Get-EntraSecurityConfig.ps1:124-128`

- [ ] **Step 1: Write a failing test for missing Global Admin role**

Add a new Context block to the existing test file:

```powershell
# In tests/Entra/Get-EntraSecurityConfig.Tests.ps1
# Add AFTER the existing Describe block closes, as a NEW Describe block:

Describe 'Get-EntraSecurityConfig - Edge Cases' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }
        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }

        # Stub Import-Module to prevent actual module loading
        Mock Import-Module { }
    }

    Context 'when Global Administrator role is not activated' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Method, $Uri)
                switch -Wildcard ($Uri) {
                    '*/directoryRoles?*Global Administrator*' {
                        return @{ value = @() }  # Empty - role not activated
                    }
                    default {
                        return @{ value = @() }
                    }
                }
            }
            . "$PSScriptRoot/../../Entra/Get-EntraSecurityConfig.ps1"
        }

        It 'should not throw' {
            $settings | Should -Not -BeNullOrEmpty
        }

        It 'should produce a Warning or Info status for admin count' {
            $adminCheck = $settings | Where-Object {
                $_.Setting -eq 'Global Administrator Count'
            }
            $adminCheck | Should -Not -BeNullOrEmpty
            $adminCheck.Status | Should -BeIn @('Warning', 'Info', 'N/A')
        }
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

File: `tests/Entra/Get-EntraSecurityConfig.Tests.ps1` (append)

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Entra/Get-EntraSecurityConfig.Tests.ps1' -Output Detailed"`
Expected: FAIL on the edge case context (IndexOutOfRangeException or similar)

- [ ] **Step 3: Add bounds check in Get-EntraSecurityConfig.ps1**

In `Entra/Get-EntraSecurityConfig.ps1`, replace lines 124-128:

```powershell
# BEFORE (unsafe):
try {
    Write-Verbose "Checking global admin count..."
    $globalAdminRole = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/directoryRoles?`$filter=displayName eq 'Global Administrator'" -ErrorAction Stop
    $roleId = $globalAdminRole['value'][0]['id']

# AFTER (safe):
try {
    Write-Verbose "Checking global admin count..."
    $globalAdminRole = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/directoryRoles?`$filter=displayName eq 'Global Administrator'" -ErrorAction Stop

    if (-not $globalAdminRole['value'] -or @($globalAdminRole['value']).Count -eq 0) {
        Write-Warning "Global Administrator directory role not activated in this tenant"
        Add-Setting -Category 'Admin Accounts' -Setting 'Global Administrator Count' `
            -CurrentValue 'Role not activated' -RecommendedValue '2-4 (excluding break-glass)' `
            -Status 'Warning' -CheckId 'ENTRA-ADMIN-001'
    }
    else {
        $roleId = $globalAdminRole['value'][0]['id']
```

Close the new `else` block after the existing admin count logic (before the catch).

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Entra/Get-EntraSecurityConfig.Tests.ps1' -Output Detailed"`
Expected: ALL tests PASS (both existing and new edge case)

- [ ] **Step 5: Lint**

Run: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './Entra/Get-EntraSecurityConfig.ps1' -Severity Warning,Error"`
Expected: No warnings or errors

- [ ] **Step 6: Commit**

```bash
git add Entra/Get-EntraSecurityConfig.ps1 tests/Entra/Get-EntraSecurityConfig.Tests.ps1
git commit -m "fix: add bounds check for Global Admin role array access (#88)"
```

---

### Task 2: Fix unsafe array access in Export-AssessmentReport.ps1 (#89)

**Files:**
- Modify: `Common/Export-AssessmentReport.ps1:140-146, 495-496`

> **Note:** This task does not include a TDD step. Export-AssessmentReport.ps1 is a ~4000-line HTML report generator that requires extensive input data to exercise. The defensive guard is simple enough to verify by inspection + PSScriptAnalyzer lint. Integration testing happens via live tenant runs.

- [ ] **Step 1: Add empty-array guard at lines 140-146**

Replace the tenantData name resolution block:

```powershell
# BEFORE:
if (-not $TenantName) {
    if ($tenantData -and $tenantData[0].PSObject.Properties.Name -contains 'OrgDisplayName') {
        $TenantName = $tenantData[0].OrgDisplayName
    }
    elseif ($tenantData -and $tenantData[0].PSObject.Properties.Name -contains 'DefaultDomain') {
        $TenantName = $tenantData[0].DefaultDomain
    }
    else {
        $TenantName = 'M365 Tenant'
    }
}

# AFTER:
if (-not $TenantName) {
    if ($tenantData -and @($tenantData).Count -gt 0 -and $tenantData[0].PSObject.Properties.Name -contains 'OrgDisplayName') {
        $TenantName = $tenantData[0].OrgDisplayName
    }
    elseif ($tenantData -and @($tenantData).Count -gt 0 -and $tenantData[0].PSObject.Properties.Name -contains 'DefaultDomain') {
        $TenantName = $tenantData[0].DefaultDomain
    }
    else {
        $TenantName = 'M365 Tenant'
    }
}
```

- [ ] **Step 2: Add empty-array guard at line 495-496**

Replace the tenant info section access:

```powershell
# BEFORE:
    if ($sectionName -eq 'Tenant' -and $tenantData) {
        $t = $tenantData[0]

# AFTER:
    if ($sectionName -eq 'Tenant' -and $tenantData -and @($tenantData).Count -gt 0) {
        $t = $tenantData[0]
```

- [ ] **Step 3: Lint**

Run: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './Common/Export-AssessmentReport.ps1' -Severity Warning,Error"`
Expected: No warnings or errors

- [ ] **Step 4: Commit**

```bash
git add Common/Export-AssessmentReport.ps1
git commit -m "fix: add empty-array guards for tenantData access (#89)"
```

---

### Task 3: Update CLAUDE.md testing policy (#91)

**Files:**
- Modify: `CLAUDE.md:6, 41-45`

- [ ] **Step 1: Update the testing line at line 6**

```markdown
# BEFORE:
- **Testing**: Pester 5.x — on demand only

# AFTER:
- **Testing**: Pester 5.x with CI integration
```

- [ ] **Step 2: Rewrite the Testing Policy section (lines 41-45)**

```markdown
# BEFORE:
## Testing Policy

> **Do NOT run Pester tests unless the user explicitly asks via `/test`.**
> Smoke tests (parse, params, help) are sufficient during development.
> Live M365 tenant testing is the primary validation method.

# AFTER:
## Testing Policy

- **Unit tests (Pester):** Run after writing or modifying collectors. Each security collector should have a corresponding `.Tests.ps1` file under `tests/`. CI runs all Pester tests automatically on push.
- **Smoke tests:** Parse validation and `Get-Help` checks run via `tests/Smoke/Script-Validation.Tests.ps1` for all scripts.
- **Live tenant testing:** Primary integration validation method. Unit tests catch regressions; live tests validate real API behavior.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "chore: update testing policy to include Pester in workflow (#91)"
```

---

### Task 3b: Org attribution (#90) -- already completed

> **No action needed.** Org attribution is already committed on the `chore/org-attribution` branch (commits `df6441b` and `55c782b`). This task exists only to acknowledge that #90 is covered by pre-existing work on this branch. The PR will close #90.

---

## Chunk 2: Pester Test Expansion (#93) - Part 1

All test files follow the established pattern from `tests/Entra/Get-EntraSecurityConfig.Tests.ps1`:
1. `BeforeAll`: stub `Update-CheckProgress`, stub connection checks, mock all external cmdlets, dot-source collector
2. Structural assertions: non-empty output, required properties, valid statuses, CheckId format
3. Spot-check 2-3 specific checks for expected status values
4. `AfterAll`: clean up global stubs

### Task 4: Add Pester tests for Get-CASecurityConfig.ps1

**Files:**
- Create: `tests/Entra/Get-CASecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-CASecurityConfig' {
    BeforeAll {
        # Stub the progress function so Add-Setting's guard passes
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        # Stub Get-MgContext so the connection check passes
        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }

        # Mock Invoke-MgGraphRequest with a comprehensive CA policy set
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            switch -Wildcard ($Uri) {
                '*/identity/conditionalAccess/policies' {
                    return @{ value = @(
                        @{
                            id = 'ca-mfa-admins'
                            displayName = 'Require MFA for admins'
                            state = 'enabled'
                            conditions = @{
                                users = @{
                                    includeRoles = @(
                                        '62e90394-69f5-4237-9190-012177145e10'  # Global Admin
                                        'fe930be7-5e62-47db-91af-98c3a49a38b1'  # User Admin
                                        '29232cdf-9323-42fd-ade2-1d097af3e4de'  # Exchange Admin
                                        'f28a1f50-f6e7-4571-818b-6a12f2af6b6c'  # SharePoint Admin
                                        '194ae4cb-b126-40b2-bd5b-6091b380977d'  # Security Admin
                                        'f2ef992c-3afb-46b9-b7cf-a126ee74c451'  # Compliance Admin
                                        '729827e3-9c14-49f7-bb1b-9608f156bbb8'  # Helpdesk Admin
                                        '966707d0-3269-4727-9be2-8c3a10f19b9d'  # Password Admin
                                        'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9'  # CA Admin
                                        'b0f54661-2d74-4c50-afa3-1ec803f12efe'  # Billing Admin
                                        '158c047a-c907-4556-b7ef-446551a6b5f7'  # Cloud App Admin
                                        '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'  # Privileged Auth Admin
                                        'e8611ab8-c189-46e8-94e1-60213ab1f814'  # Privileged Role Admin
                                        '9360feb5-f418-4baa-8175-e2a00bac4301'  # Directory Writer
                                    )
                                    excludeUsers = @()
                                }
                                applications = @{ includeApplications = @('All') }
                                clientAppTypes = @('all')
                            }
                            grantControls = @{
                                builtInControls = @('mfa')
                                operator = 'OR'
                            }
                        }
                        @{
                            id = 'ca-mfa-all'
                            displayName = 'Require MFA for all users'
                            state = 'enabled'
                            conditions = @{
                                users = @{
                                    includeUsers = @('All')
                                    excludeUsers = @()
                                }
                                applications = @{ includeApplications = @('All') }
                                clientAppTypes = @('all')
                            }
                            grantControls = @{
                                builtInControls = @('mfa')
                                operator = 'OR'
                            }
                        }
                        @{
                            id = 'ca-block-legacy'
                            displayName = 'Block legacy authentication'
                            state = 'enabled'
                            conditions = @{
                                users = @{ includeUsers = @('All') }
                                applications = @{ includeApplications = @('All') }
                                clientAppTypes = @('exchangeActiveSync', 'other')
                            }
                            grantControls = @{
                                builtInControls = @('block')
                                operator = 'OR'
                            }
                        }
                        @{
                            id = 'ca-user-risk'
                            displayName = 'User risk remediation'
                            state = 'enabled'
                            conditions = @{
                                users = @{ includeUsers = @('All') }
                                applications = @{ includeApplications = @('All') }
                                userRiskLevels = @('high')
                            }
                            grantControls = @{
                                builtInControls = @('mfa', 'passwordChange')
                                operator = 'AND'
                            }
                        }
                        @{
                            id = 'ca-signin-risk'
                            displayName = 'Sign-in risk block'
                            state = 'enabled'
                            conditions = @{
                                users = @{ includeUsers = @('All') }
                                applications = @{ includeApplications = @('All') }
                                signInRiskLevels = @('high', 'medium')
                            }
                            grantControls = @{
                                builtInControls = @('block')
                                operator = 'OR'
                            }
                        }
                    )}
                }
                default {
                    return @{ value = @() }
                }
            }
        }

        # Run the collector
        . "$PSScriptRoot/../../Entra/Get-CASecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CurrentValue'
            $s.PSObject.Properties.Name | Should -Contain 'RecommendedValue'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All Status values are valid' {
        $validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'N/A')
        foreach ($s in $settings) {
            $s.Status | Should -BeIn $validStatuses `
                -Because "Setting '$($s.Setting)' has status '$($s.Status)'"
        }
    }

    It 'All non-empty CheckIds follow naming convention' {
        $withCheckId = $settings | Where-Object { $_.CheckId -and $_.CheckId.Trim() -ne '' }
        $withCheckId.Count | Should -BeGreaterThan 0
        foreach ($s in $withCheckId) {
            $s.CheckId | Should -Match '^CA-[A-Z0-9]+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow CA-* convention"
        }
    }

    It 'MFA for admins check passes with correct policy' {
        $check = $settings | Where-Object { $_.CheckId -like 'CA-MFA-ADMIN-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'Legacy auth block check passes with correct policy' {
        $check = $settings | Where-Object { $_.CheckId -like 'CA-LEGACYAUTH-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'Produces all 12 CA checks' {
        $settings.Count | Should -BeGreaterOrEqual 12
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Entra/Get-CASecurityConfig.Tests.ps1' -Output Detailed"`
Expected: PASS

- [ ] **Step 3: Lint test file**

Run: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Entra/Get-CASecurityConfig.Tests.ps1' -Severity Warning,Error"`

- [ ] **Step 4: Commit**

```bash
git add tests/Entra/Get-CASecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for CA security collector (#93)"
```

---

### Task 5: Add Pester tests for Get-ExoSecurityConfig.ps1

**Files:**
- Create: `tests/Exchange-Online/Get-ExoSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

This collector has the most external cmdlets (13+). Key mocking pattern:

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-ExoSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        # Stub EXO connection check — collector verifies via Get-OrganizationConfig
        Mock Get-OrganizationConfig {
            return @{
                OAuth2ClientProfileEnabled = $true
                AuditDisabled              = $false
                CustomerLockBoxEnabled     = $true
                MailTipsAllTipsEnabled      = $true
                MailTipsExternalRecipientsTipsEnabled = $true
                MailTipsGroupMetricsEnabled = $true
                MailTipsLargeAudienceThreshold = 25
                AutoForwardEnabled         = $false
                SmtpClientAuthenticationDisabled = $true
            }
        }
        Mock Get-ExternalInOutlook {
            return @{ Enabled = $true }
        }
        Mock Get-RemoteDomain {
            return @{ AutoForwardEnabled = $false }
        }
        Mock Get-OwaMailboxPolicy {
            return @{ AdditionalStorageProvidersAvailable = $false }
        }
        Mock Get-SharingPolicy {
            return @{
                Domains = @('*:CalendarSharingFreeBusySimple')
                Enabled = $true
            }
        }
        Mock Get-MailboxAuditBypassAssociation {
            return @()
        }
        Mock Get-TransportConfig {
            return @{ SmtpClientAuthenticationDisabled = $true }
        }
        Mock Get-RoleAssignmentPolicy {
            return @{
                AssignedRoles = @('MyBaseOptions', 'MyContactInformation', 'MyProfileInformation')
            }
        }
        Mock Get-HostedConnectionFilterPolicy {
            return @{
                IPAllowList = @()
                EnableSafeList = $false
            }
        }
        Mock Get-TransportRule {
            return @()
        }
        Mock Get-Mailbox {
            return @(
                @{
                    DisplayName = 'Test Shared'
                    UserPrincipalName = 'shared@contoso.com'
                    RecipientTypeDetails = 'SharedMailbox'
                    AccountDisabled = $true
                }
            )
        }
        Mock Get-Command { return $true }
        Mock Get-InboundConnector { return @() }
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            return @{ accountEnabled = $false }
        }

        . "$PSScriptRoot/../../Exchange-Online/Get-ExoSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CurrentValue'
            $s.PSObject.Properties.Name | Should -Contain 'RecommendedValue'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All Status values are valid' {
        $validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'N/A')
        foreach ($s in $settings) {
            $s.Status | Should -BeIn $validStatuses `
                -Because "Setting '$($s.Setting)' has status '$($s.Status)'"
        }
    }

    It 'All non-empty CheckIds follow naming convention' {
        $withCheckId = $settings | Where-Object { $_.CheckId -and $_.CheckId.Trim() -ne '' }
        $withCheckId.Count | Should -BeGreaterThan 0
        foreach ($s in $withCheckId) {
            $s.CheckId | Should -Match '^EXO-[A-Z0-9]+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow EXO-* convention"
        }
    }

    It 'Modern auth check passes when enabled' {
        $check = $settings | Where-Object { $_.CheckId -like 'EXO-AUTH-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'Audit check passes when enabled' {
        $check = $settings | Where-Object { $_.CheckId -like 'EXO-AUDIT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'Produces checks across multiple categories' {
        $categories = $settings | Select-Object -ExpandProperty Category -Unique
        $categories.Count | Should -BeGreaterOrEqual 3
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Exchange-Online/Get-ExoSecurityConfig.Tests.ps1' -Output Detailed"`
Expected: PASS

- [ ] **Step 3: Lint and commit**

```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Exchange-Online/Get-ExoSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Exchange-Online/Get-ExoSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for EXO security collector (#93)"
```

---

### Task 6: Add Pester tests for Get-DnsSecurityConfig.ps1

**Files:**
- Create: `tests/Exchange-Online/Get-DnsSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-DnsSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        Mock Get-AcceptedDomain {
            return @(
                @{ DomainName = 'contoso.com'; Default = $true }
            )
        }

        Mock Resolve-DnsName {
            param($Name, $Type)
            if ($Name -like '*._dmarc.*') {
                return @(@{ Strings = @('v=DMARC1; p=reject; rua=mailto:dmarc@contoso.com') })
            }
            elseif ($Name -like '*selector1._domainkey*' -or $Name -like '*selector2._domainkey*') {
                return @(@{ Strings = @('v=DKIM1; k=rsa; p=MIGfMA0GCS...') })
            }
            else {
                # SPF record
                return @(@{ Strings = @('v=spf1 include:spf.protection.outlook.com -all') })
            }
        }

        Mock Get-Command { return $true }
        Mock Get-DkimSigningConfig {
            return @(
                @{ Domain = 'contoso.com'; Enabled = $true; Status = 'Valid' }
            )
        }

        . "$PSScriptRoot/../../Exchange-Online/Get-DnsSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'SPF check passes with valid record' {
        $check = $settings | Where-Object { $_.CheckId -like 'DNS-SPF-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'DMARC check passes with reject policy' {
        $check = $settings | Where-Object { $_.CheckId -like 'DNS-DMARC-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test, lint, commit**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Exchange-Online/Get-DnsSecurityConfig.Tests.ps1' -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Exchange-Online/Get-DnsSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Exchange-Online/Get-DnsSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for DNS security collector (#93)"
```

---

### Task 7: Add Pester tests for Get-DefenderSecurityConfig.ps1

**Files:**
- Create: `tests/Security/Get-DefenderSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

This is the largest collector (~35 checks). Mock all Defender cmdlets:

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-DefenderSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        Mock Get-AntiPhishPolicy {
            return @(
                @{
                    Identity = 'Office365 AntiPhish Default'
                    IsDefault = $true
                    PhishThresholdLevel = 3
                    EnableMailboxIntelligence = $true
                    EnableMailboxIntelligenceProtection = $true
                    EnableTargetedUserProtection = $true
                    EnableTargetedDomainsProtection = $true
                    EnableOrganizationDomainsProtection = $true
                    HonorDmarcPolicy = $true
                    EnableSpoofIntelligence = $true
                    EnableFirstContactSafetyTips = $true
                    EnableSimilarUsersSafetyTips = $true
                    EnableSimilarDomainsSafetyTips = $true
                    EnableUnusualCharactersSafetyTips = $true
                    TargetedUserProtectionAction = 'Quarantine'
                    TargetedDomainProtectionAction = 'Quarantine'
                    MailboxIntelligenceProtectionAction = 'MoveToJmf'
                }
            )
        }

        Mock Get-HostedContentFilterPolicy {
            return @(
                @{
                    Identity = 'Default'
                    IsDefault = $true
                    BulkThreshold = 6
                    SpamAction = 'MoveToJmf'
                    HighConfidenceSpamAction = 'Quarantine'
                    PhishSpamAction = 'Quarantine'
                    HighConfidencePhishAction = 'Quarantine'
                    SpamZapEnabled = $true
                    PhishZapEnabled = $true
                    BulkSpamAction = 'MoveToJmf'
                    AllowedSenderDomains = @()
                    AllowedSenders = @()
                }
            )
        }

        Mock Get-MalwareFilterPolicy {
            return @(
                @{
                    Identity = 'Default'
                    IsDefault = $true
                    EnableFileFilter = $true
                    ZapEnabled = $true
                    EnableInternalSenderAdminNotifications = $false
                    FileTypes = @('.exe', '.bat', '.cmd', '.ps1')
                }
            )
        }

        Mock Get-Command { return $true }
        Mock Get-SafeLinksPolicy {
            return @(
                @{
                    Identity = 'Built-In Protection Policy'
                    IsBuiltInProtection = $true
                    EnableSafeLinksForEmail = $true
                    EnableSafeLinksForTeams = $true
                    EnableSafeLinksForOffice = $true
                    TrackClicks = $true
                    ScanUrls = $true
                    EnableForInternalSenders = $true
                    DeliverMessageAfterScan = $true
                    DisableUrlRewrite = $false
                }
            )
        }
        Mock Get-SafeAttachmentPolicy {
            return @(
                @{
                    Identity = 'Built-In Protection Policy'
                    IsBuiltInProtection = $true
                    Enable = $true
                    Action = 'Block'
                    Redirect = $false
                    RedirectAddress = ''
                }
            )
        }
        Mock Get-AtpPolicyForO365 {
            return @{
                EnableSafeDocs = $true
                EnableATPForSPOTeamsODB = $true
                AllowSafeDocsOpen = $false
            }
        }
        Mock Get-HostedOutboundSpamFilterPolicy {
            return @(
                @{
                    Identity = 'Default'
                    AutoForwardingMode = 'Off'
                    NotifyOutboundSpam = $true
                    NotifyOutboundSpamRecipients = @('admin@contoso.com')
                    BccSuspiciousOutboundMail = $true
                    BccSuspiciousOutboundAdditionalRecipients = @('sec@contoso.com')
                }
            )
        }
        Mock Get-EOPProtectionPolicyRule {
            return @(
                @{ Identity = 'Strict Preset Security Policy'; State = 'Enabled'; Priority = 0 }
                @{ Identity = 'Standard Preset Security Policy'; State = 'Enabled'; Priority = 1 }
            )
        }

        . "$PSScriptRoot/../../Security/Get-DefenderSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All Status values are valid' {
        $validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'N/A')
        foreach ($s in $settings) {
            $s.Status | Should -BeIn $validStatuses `
                -Because "Setting '$($s.Setting)' has status '$($s.Status)'"
        }
    }

    It 'All non-empty CheckIds follow naming convention' {
        $withCheckId = $settings | Where-Object { $_.CheckId -and $_.CheckId.Trim() -ne '' }
        $withCheckId.Count | Should -BeGreaterThan 0
        foreach ($s in $withCheckId) {
            $s.CheckId | Should -Match '^DEFENDER-[A-Z0-9]+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow DEFENDER-* convention"
        }
    }

    It 'Anti-phish threshold check produces a result' {
        $check = $settings | Where-Object { $_.CheckId -like 'DEFENDER-ANTIPHISH-001*' -and $_.Setting -match 'Phish.*Threshold' }
        $check | Should -Not -BeNullOrEmpty
    }

    It 'Produces checks across multiple categories' {
        $categories = $settings | Select-Object -ExpandProperty Category -Unique
        $categories.Count | Should -BeGreaterOrEqual 3
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test, lint, commit**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Security/Get-DefenderSecurityConfig.Tests.ps1' -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Security/Get-DefenderSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Security/Get-DefenderSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for Defender security collector (#93)"
```

---

## Chunk 3: Pester Test Expansion (#93) - Part 2

### Task 8: Add Pester tests for Get-ComplianceSecurityConfig.ps1

**Files:**
- Create: `tests/Security/Get-ComplianceSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-ComplianceSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        # All three cmdlets are optional (checked via Get-Command)
        Mock Get-Command { return $true }
        Mock Get-AdminAuditLogConfig {
            return @{
                UnifiedAuditLogIngestionEnabled = $true
            }
        }
        Mock Get-DlpCompliancePolicy {
            return @(
                @{
                    Name = 'Default DLP Policy'
                    Enabled = $true
                    Workload = 'Exchange, SharePoint, OneDriveForBusiness, Teams'
                    Mode = 'Enable'
                }
            )
        }
        Mock Get-LabelPolicy {
            return @(
                @{ Name = 'Default Sensitivity Labels'; Enabled = $true }
            )
        }

        . "$PSScriptRoot/../../Security/Get-ComplianceSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All Status values are valid' {
        $validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'N/A')
        foreach ($s in $settings) {
            $s.Status | Should -BeIn $validStatuses `
                -Because "Setting '$($s.Setting)' has status '$($s.Status)'"
        }
    }

    It 'Unified audit log check passes when enabled' {
        $check = $settings | Where-Object { $_.CheckId -like 'COMPLIANCE-AUDIT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'DLP policy check passes when policies exist' {
        $check = $settings | Where-Object { $_.CheckId -like 'COMPLIANCE-DLP-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test, lint, commit**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Security/Get-ComplianceSecurityConfig.Tests.ps1' -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Security/Get-ComplianceSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Security/Get-ComplianceSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for Compliance security collector (#93)"
```

---

### Task 9: Add Pester tests for Get-IntuneSecurityConfig.ps1

**Files:**
- Create: `tests/Intune/Get-IntuneSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-IntuneSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            switch -Wildcard ($Uri) {
                '*/beta/deviceManagement/settings' {
                    return @{
                        deviceComplianceCheckinThresholdDays = 30
                    }
                }
                '*/beta/deviceManagement/deviceEnrollmentConfigurations' {
                    return @{ value = @(
                        @{
                            '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration'
                            platformType = 'windows'
                            platformRestriction = @{
                                personalDeviceEnrollmentBlocked = $true
                            }
                        }
                    )}
                }
                default {
                    return @{ value = @() }
                }
            }
        }

        . "$PSScriptRoot/../../Intune/Get-IntuneSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All non-empty CheckIds follow naming convention' {
        $withCheckId = $settings | Where-Object { $_.CheckId -and $_.CheckId.Trim() -ne '' }
        $withCheckId.Count | Should -BeGreaterThan 0
        foreach ($s in $withCheckId) {
            $s.CheckId | Should -Match '^INTUNE-[A-Z0-9]+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow INTUNE-* convention"
        }
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test, lint, commit**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Intune/Get-IntuneSecurityConfig.Tests.ps1' -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Intune/Get-IntuneSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Intune/Get-IntuneSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for Intune security collector (#93)"
```

---

### Task 10: Add Pester tests for Get-SharePointSecurityConfig.ps1

**Files:**
- Create: `tests/Collaboration/Get-SharePointSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-SharePointSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            switch -Wildcard ($Uri) {
                '*/v1.0/admin/sharepoint/settings' {
                    return @{
                        sharingCapability = 'existingExternalUserSharingOnly'
                        isResharingByExternalUsersEnabled = $false
                        sharingDomainRestrictionMode = 'allowList'
                        sharingAllowedDomainList = @('partner.com')
                        defaultSharingLinkType = 'specificPeople'
                        externalUserExpirationRequired = $true
                        externalUserExpireInDays = 30
                        isLoopEnabled = $false
                        isOneDriveLoopEnabled = $false
                        idleSessionSignOut = @{
                            isEnabled = $true
                            warnAfterInSeconds = 3300
                            signOutAfterInSeconds = 3600
                        }
                        legacyAuthProtocolsEnabled = $false
                        isUnmanagedSyncClientForTenantRestricted = $true
                        isFluidEnabled = $false
                        isMacSyncAppEnabled = $true
                        defaultLinkPermission = 'view'
                    }
                }
                '*/beta/admin/sharepoint/settings' {
                    return @{
                        isCollabMeetingNotesFluidEnabled = $false
                        personalSiteDefaultStorageLimitInMB = 1048576
                    }
                }
                '*/v1.0/policies/activityBasedTimeoutPolicies' {
                    return @{ value = @(
                        @{ definition = @('{"ActivityBasedTimeoutPolicy":{"Version":1,"ApplicationPolicies":[{"ApplicationId":"*","WebSessionIdleTimeout":"01:00:00"}]}}') }
                    )}
                }
                default {
                    return @{ value = @() }
                }
            }
        }

        . "$PSScriptRoot/../../Collaboration/Get-SharePointSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All Status values are valid' {
        $validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'N/A')
        foreach ($s in $settings) {
            $s.Status | Should -BeIn $validStatuses `
                -Because "Setting '$($s.Setting)' has status '$($s.Status)'"
        }
    }

    It 'All non-empty CheckIds follow naming convention' {
        $withCheckId = $settings | Where-Object { $_.CheckId -and $_.CheckId.Trim() -ne '' }
        $withCheckId.Count | Should -BeGreaterThan 0
        foreach ($s in $withCheckId) {
            $s.CheckId | Should -Match '^SPO-[A-Z0-9]+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow SPO-* convention"
        }
    }

    It 'Sharing level check produces a result' {
        $check = $settings | Where-Object { $_.CheckId -like 'SPO-SHARING-001*' }
        $check | Should -Not -BeNullOrEmpty
    }

    It 'Produces checks across multiple categories' {
        $categories = $settings | Select-Object -ExpandProperty Category -Unique
        $categories.Count | Should -BeGreaterOrEqual 2
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test, lint, commit**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Collaboration/Get-SharePointSecurityConfig.Tests.ps1' -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Collaboration/Get-SharePointSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Collaboration/Get-SharePointSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for SharePoint security collector (#93)"
```

---

### Task 11: Add Pester tests for Get-TeamsSecurityConfig.ps1

**Files:**
- Create: `tests/Collaboration/Get-TeamsSecurityConfig.Tests.ps1`

- [ ] **Step 1: Create test file**

This collector has early-exit paths (no Teams license, app-only auth). Test the happy path first:

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-TeamsSecurityConfig' {
    BeforeAll {
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        function Get-MgContext {
            return @{
                TenantId = 'test-tenant-id'
                AuthType = 'Delegated'
                AppName = 'Microsoft Graph PowerShell'
            }
        }

        Mock Get-MgSubscribedSku {
            return @(
                @{
                    ServicePlans = @(
                        @{ ServicePlanId = '57ff2da0-773e-42df-b2af-ffb7a2317929'; ProvisioningStatus = 'Success' }
                    )
                }
            )
        }

        Mock Invoke-MgGraphRequest {
            param($Method, $Uri)
            switch -Wildcard ($Uri) {
                '*/v1.0/teamwork/teamsAppSettings' {
                    return @{
                        isChatResourceSpecificConsentEnabled = $false
                    }
                }
                '*/beta/teamwork/teamsClientConfiguration' {
                    return @{
                        allowDropBox = $false
                        allowGoogleDrive = $false
                        allowBox = $false
                        allowEgnyte = $false
                        allowShareFile = $false
                        allowEmailIntoChannel = $false
                    }
                }
                '*/beta/teamwork/teamsMeetingPolicy*' {
                    return @{
                        value = @(@{
                            identity = 'Global'
                            allowAnonymousUsersToJoinMeeting = $false
                            allowAnonymousUsersToStartMeeting = $false
                            autoAdmittedUsers = 'EveryoneInCompanyExcludingGuests'
                            allowPSTNUsersToBypassLobby = $false
                            designatedPresenterRoleMode = 'OrganizerOnlyUserOverride'
                            allowMeetingChat = 'Enabled'
                            allowCloudRecording = $true
                            allowExternalParticipantGiveRequestControl = $false
                        })
                    }
                }
                '*/v1.0/teamwork' {
                    return @{ id = 'teams-active' }
                }
                default {
                    return @{ value = @() }
                }
            }
        }

        . "$PSScriptRoot/../../Collaboration/Get-TeamsSecurityConfig.ps1"
    }

    It 'Returns a non-empty settings list' {
        $settings.Count | Should -BeGreaterThan 0
    }

    It 'All settings have required properties' {
        foreach ($s in $settings) {
            $s.PSObject.Properties.Name | Should -Contain 'Category'
            $s.PSObject.Properties.Name | Should -Contain 'Setting'
            $s.PSObject.Properties.Name | Should -Contain 'Status'
            $s.PSObject.Properties.Name | Should -Contain 'CheckId'
        }
    }

    It 'All Status values are valid' {
        $validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'N/A')
        foreach ($s in $settings) {
            $s.Status | Should -BeIn $validStatuses `
                -Because "Setting '$($s.Setting)' has status '$($s.Status)'"
        }
    }

    It 'All non-empty CheckIds follow naming convention' {
        $withCheckId = $settings | Where-Object { $_.CheckId -and $_.CheckId.Trim() -ne '' }
        $withCheckId.Count | Should -BeGreaterThan 0
        foreach ($s in $withCheckId) {
            $s.CheckId | Should -Match '^TEAMS-[A-Z0-9]+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow TEAMS-* convention"
        }
    }

    It 'Third-party cloud storage check passes when disabled' {
        $check = $settings | Where-Object { $_.CheckId -like 'TEAMS-CLIENT-001*' }
        $check | Should -Not -BeNullOrEmpty
        $check.Status | Should -Be 'Pass'
    }

    It 'Produces checks across multiple categories' {
        $categories = $settings | Select-Object -ExpandProperty Category -Unique
        $categories.Count | Should -BeGreaterOrEqual 2
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run test, lint, commit**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Collaboration/Get-TeamsSecurityConfig.Tests.ps1' -Output Detailed"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './tests/Collaboration/Get-TeamsSecurityConfig.Tests.ps1' -Severity Warning,Error"
git add tests/Collaboration/Get-TeamsSecurityConfig.Tests.ps1
git commit -m "test: add Pester tests for Teams security collector (#93)"
```

---

## Chunk 4: CHANGELOG, Version Bump, and Finalization

### Task 12: Run full test suite to verify all new tests pass

- [ ] **Step 1: Run all Pester tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path './tests' -Output Detailed"`
Expected: ALL tests pass (existing + 8 new test files)

- [ ] **Step 2: Run PSScriptAnalyzer on all modified files**

Run: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path '.' -Recurse -ExcludeRule PSUseDeclaredVarsMoreThanAssignments -Severity Warning,Error | Format-Table -AutoSize"`
Expected: No warnings or errors on modified files

---

### Task 13: Update CHANGELOG.md (#94)

**Files:**
- Modify: `CHANGELOG.md` (add new section above existing v0.8.1 entry)

- [ ] **Step 1: Add consolidated CHANGELOG entries**

Insert above the `## [0.8.1]` line:

```markdown
## [0.8.4] - 2026-03-14

### Added
- Pester unit tests for all 9 security config collectors (CA, EXO, DNS, Defender, Compliance, Intune, SharePoint, Teams + existing Entra)
- Edge case test for missing Global Administrator directory role

### Changed
- Org attribution updated to SelvageLabs across repository
- CLAUDE.md testing policy updated: Pester tests are now part of standard workflow (previously "on demand only")

### Fixed
- Unsafe array access in Get-EntraSecurityConfig.ps1 when Global Admin role is not activated (#88)
- Unsafe array access in Export-AssessmentReport.ps1 when tenantData is empty (#89)

## [0.8.3] - 2026-03-14

### Added
- Dark mode toggle with CSS variable theming and accessibility improvements
- Email report section redesigned with improved flow and categorization

### Fixed
- Print/PDF layout broken for client delivery (#78)
- MFA adoption metric using proxy data instead of registration status (#76)

## [0.8.2] - 2026-03-14

### Added
- GitHub Actions CI pipeline: PSScriptAnalyzer, Pester tests, version consistency checks
- 137 Pester tests across smoke, Entra, registry, and control integrity suites
- Dependency pinning with compatibility matrix

### Fixed
- Global admin count now excludes breakglass accounts (#72)
```

- [ ] **Step 2: Commit CHANGELOG**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG entries for v0.8.2, v0.8.3, v0.8.4 (#94)"
```

---

### Task 14: Version bump (all 30 locations)

> **IMPORTANT:** Do NOT execute this task until the user explicitly approves the version bump per `.claude/rules/releases.md`.

**Files:** All 30 locations listed in `.claude/rules/versions.md`
- Update `0.8.1` to `0.8.4` in all Core, Common helper, Security config, Other collector, and Documentation files

- [ ] **Step 1: Ask user for version bump approval**

> "All v0.8.4 work is complete. This warrants a version bump from 0.8.1 to 0.8.4. Should I increment the version?"

- [ ] **Step 2: Verify current version string before replacing**

Run: `pwsh -NoProfile -Command "Select-String -Path *.ps1,**/*.ps1,README.md,M365-Assess.psd1 -Pattern 'Version:\s+\d+\.\d+\.\d+|AssessmentVersion\s*=|version-\d+\.\d+\.\d+|ModuleVersion' | Sort-Object Path"`

Confirm all locations show `0.8.1`. If any show a different version (e.g., `0.8.0`), adjust the replacement pattern accordingly.

- [ ] **Step 3: Update all 30 version locations**

Update `0.8.1` to `0.8.4` in every file listed in `.claude/rules/versions.md`. Use find-and-replace per file, targeting only the version string in `.NOTES` blocks and variable assignments.

- [ ] **Step 4: Verify version consistency**

Run: `pwsh -NoProfile -Command "Select-String -Path *.ps1,**/*.ps1,README.md,M365-Assess.psd1 -Pattern 'Version:\s+\d+\.\d+\.\d+|AssessmentVersion\s*=|version-\d+\.\d+\.\d+|ModuleVersion' | Sort-Object Path"`
Expected: All locations show `0.8.4`

- [ ] **Step 5: Run CI checks locally**

```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path '.' -Recurse -ExcludeRule PSUseDeclaredVarsMoreThanAssignments -Severity Warning,Error"
pwsh -NoProfile -Command "Invoke-Pester -Path './tests' -Output Detailed"
```

- [ ] **Step 6: Commit version bump**

```bash
git add -A
git commit -m "chore: bump version to 0.8.4 (#88, #89, #90, #91, #93, #94)"
```

---

### Task 15: Create PR and close issues

- [ ] **Step 1: Push branch and create PR**

```bash
git push -u origin chore/org-attribution
gh pr create --title "chore: v0.8.4 hardening and housekeeping" --milestone "v0.8.4 - Hardening & Housekeeping" --body "$(cat <<'EOF'
## Summary

- fix: unsafe array access in Get-EntraSecurityConfig.ps1 (#88)
- fix: unsafe array access in Export-AssessmentReport.ps1 (#89)
- chore: org attribution migration to SelvageLabs (#90)
- chore: update CLAUDE.md testing policy (#91)
- test: Pester coverage for all 9 security collectors (#93)
- docs: CHANGELOG entries for v0.8.2, v0.8.3, v0.8.4 (#94)
- chore: version bump to 0.8.4

## Test plan

- [ ] All Pester tests pass locally
- [ ] PSScriptAnalyzer clean
- [ ] Version consistency check passes (all 30 locations show 0.8.4)
- [ ] CI pipeline passes on PR

Closes #88, #89, #90, #91, #93, #94
EOF
)"
```

- [ ] **Step 2: After merge, create GitHub release**

> Ask user before creating release tag.

```bash
gh release create v0.8.4 --title "v0.8.4" --notes "See CHANGELOG.md for details"
```
