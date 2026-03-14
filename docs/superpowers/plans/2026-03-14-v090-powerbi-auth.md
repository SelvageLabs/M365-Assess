# v0.9.0: Power BI Collector + Auth Enhancement Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Power BI security config collector (11 CIS 9.x checks) to achieve 100% CIS v6.0.1 automated coverage, and enhance authentication to reduce duplicate prompts and expose missing auth methods.

**Architecture:** Two independent workstreams: (1) A new `PowerBI/Get-PowerBISecurityConfig.ps1` collector using the `MicrosoftPowerBIMgmt` module with `Get-PowerBITenantSetting` cmdlet, wired into the orchestrator as a new section. (2) Auth enhancements in `Invoke-M365Assessment.ps1` to reorder collectors (all EXO before Purview), expose `-ClientSecret` and `-ManagedIdentity` parameters, and improve connection UX.

**Tech Stack:** PowerShell 7.x, MicrosoftPowerBIMgmt module, Microsoft Graph SDK 2.x, Pester 5.x

---

## Scope

Two issues, two independent subsystems:

| Issue | Workstream | Files |
|-------|-----------|-------|
| #66 | Power BI collector (11 CIS checks) | New: `PowerBI/Get-PowerBISecurityConfig.ps1`, `tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1`. Modify: `Invoke-M365Assessment.ps1`, `Common/Connect-Service.ps1`, `controls/registry.json` |
| #84 | Auth enhancement | Modify: `Invoke-M365Assessment.ps1`, `Common/Connect-Service.ps1`, `AUTHENTICATION.md` |

Both workstreams modify `Invoke-M365Assessment.ps1` and `Connect-Service.ps1`, so they must be sequenced (Power BI first, then auth).

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `PowerBI/Get-PowerBISecurityConfig.ps1` | Collector for 11 CIS 9.1.x Power BI tenant settings |
| `tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1` | Pester 5 mock-based tests for the collector |

### Modified Files
| File | Changes |
|------|---------|
| `Invoke-M365Assessment.ps1` | Add PowerBI section (ValidateSet, service map, scope map, module map, collector map, wizard), reorder Security section collectors, add `-ClientSecret`/`-ManagedIdentity` params |
| `Common/Connect-Service.ps1` | Add `PowerBI` service support, add `-ManagedIdentity` switch for Graph + EXO |
| `controls/registry.json` | Update 11 MANUAL-CIS-9-1-* entries: set `automated: true`, assign proper checkIds, set collector to `PowerBI` |
| `AUTHENTICATION.md` | Document new auth methods, updated prompt count expectations |
| `docs/COMPATIBILITY.md` | Add MicrosoftPowerBIMgmt to optional modules |
| `M365-Assess.psd1` | Add PowerBI to FunctionsToExport/description if needed |

---

## Chunk 1: Power BI Collector

### Task 1: Create Power BI collector skeleton with tests

**Files:**
- Create: `PowerBI/Get-PowerBISecurityConfig.ps1`
- Create: `tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1`

- [ ] **Step 1: Create the test file with structural tests**

Create `tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1`:

```powershell
BeforeDiscovery {
    # Nothing needed at discovery time
}

Describe 'Get-PowerBISecurityConfig' {
    BeforeAll {
        # Stub progress function so Add-Setting's guard passes
        function global:Update-CheckProgress {
            param($CheckId, $Setting, $Status)
        }

        # Stub Get-MgContext so the connection check passes
        function Get-MgContext { return @{ TenantId = 'test-tenant-id' } }

        # Stub Import-Module to prevent actual module loading
        Mock Import-Module { }

        # Stub Connect-PowerBIServiceAccount so connection check passes
        function Connect-PowerBIServiceAccount { }
        function Get-PowerBIAccessToken { return @{ 'Authorization' = 'Bearer test-token' } }

        # Mock Invoke-PowerBIRestMethod for tenant settings
        Mock Invoke-PowerBIRestMethod {
            param($Url, $Method)
            return @{
                tenantSettings = @(
                    @{ settingName = 'AllowExternalDataSharingReceiverWorksWithShare'; isEnabled = $false; title = 'External sharing' }
                    @{ settingName = 'AllowGuestUserToAccessSharedContent'; isEnabled = $false; title = 'Guest access to content' }
                    @{ settingName = 'AllowGuestLookup'; isEnabled = $false; title = 'Guest user access' }
                    @{ settingName = 'ElevatedGuestsTenant'; isEnabled = $false; title = 'External invitations' }
                    @{ settingName = 'WebDashboardsPublishToWebDisabled'; isEnabled = $true; title = 'Publish to web disabled' }
                    @{ settingName = 'RScriptVisuals'; isEnabled = $false; title = 'R and Python visuals' }
                    @{ settingName = 'UseSensitivityLabels'; isEnabled = $true; title = 'Sensitivity labels' }
                    @{ settingName = 'ShareLinkToEntireOrg'; isEnabled = $false; title = 'Shareable links' }
                    @{ settingName = 'BlockResourceKeyAuthentication'; isEnabled = $true; title = 'Block ResourceKey Auth' }
                    @{ settingName = 'ServicePrincipalAccess'; isEnabled = $false; title = 'Service Principal API access' }
                    @{ settingName = 'CreateServicePrincipalProfile'; isEnabled = $false; title = 'Service Principal profiles' }
                )
            }
        }

        # Run the collector by dot-sourcing it
        . "$PSScriptRoot/../../PowerBI/Get-PowerBISecurityConfig.ps1"
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
            $s.CheckId | Should -Match '^[A-Z]+(-[A-Z0-9]+)+-\d{3}(\.\d+)?$' `
                -Because "CheckId '$($s.CheckId)' should follow convention"
        }
    }

    It 'Produces exactly 11 CIS 9.x checks' {
        $cisChecks = $settings | Where-Object { $_.CheckId -match '^POWERBI-' }
        $cisChecks.Count | Should -BeGreaterOrEqual 11
    }

    It 'Guest access restriction check produces correct status' {
        $guestCheck = $settings | Where-Object {
            $_.CheckId -like 'POWERBI-GUEST-001*' -and $_.Setting -eq 'Guest User Access Restricted'
        }
        $guestCheck | Should -Not -BeNullOrEmpty
        $guestCheck.Status | Should -Be 'Pass'
    }

    It 'Publish to web restriction check produces correct status' {
        $publishCheck = $settings | Where-Object {
            $_.CheckId -like 'POWERBI-SHARING-001*' -and $_.Setting -eq 'Publish to Web Restricted'
        }
        $publishCheck | Should -Not -BeNullOrEmpty
        $publishCheck.Status | Should -Be 'Pass'
    }

    AfterAll {
        Remove-Item Function:\Update-CheckProgress -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1 -Output Detailed"
```
Expected: FAIL (collector script doesn't exist yet)

- [ ] **Step 3: Create the Power BI collector**

Create `PowerBI/Get-PowerBISecurityConfig.ps1`:

```powershell
<#
.SYNOPSIS
    Collects Power BI security and tenant configuration settings.
.DESCRIPTION
    Queries Power BI tenant settings for security-relevant configuration including
    guest access, external sharing, publish to web, sensitivity labels, and service
    principal restrictions. Returns a structured inventory of settings with current
    values and CIS benchmark recommendations.

    Requires the MicrosoftPowerBIMgmt PowerShell module.
    Uses Invoke-PowerBIRestMethod to query the admin API.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service PowerBI
    PS> .\PowerBI\Get-PowerBISecurityConfig.ps1

    Displays Power BI security configuration settings.
.EXAMPLE
    PS> .\PowerBI\Get-PowerBISecurityConfig.ps1 -OutputPath '.\powerbi-security-config.csv'

    Exports the security configuration to CSV.
.NOTES
    Version: 0.8.1
    Author:  Daren9m
    Settings checked are aligned with CIS Microsoft 365 Foundations Benchmark v6.0.1 recommendations.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify Power BI connection by attempting to get an access token
try {
    $pbiToken = Get-PowerBIAccessToken -ErrorAction Stop
    if (-not $pbiToken) {
        Write-Error "Not connected to Power BI. Run Connect-PowerBIServiceAccount first."
        return
    }
}
catch {
    Write-Error "Not connected to Power BI. Run Connect-PowerBIServiceAccount first."
    return
}

$settings = [System.Collections.Generic.List[PSCustomObject]]::new()
$checkIdCounter = @{}

function Add-Setting {
    param(
        [string]$Category,
        [string]$Setting,
        [string]$CurrentValue,
        [string]$RecommendedValue,
        [string]$Status,
        [string]$CheckId = '',
        [string]$Remediation = ''
    )
    $subCheckId = $CheckId
    if ($CheckId) {
        if (-not $checkIdCounter.ContainsKey($CheckId)) { $checkIdCounter[$CheckId] = 0 }
        $checkIdCounter[$CheckId]++
        $subCheckId = "$CheckId.$($checkIdCounter[$CheckId])"
    }
    $settings.Add([PSCustomObject]@{
        Category         = $Category
        Setting          = $Setting
        CurrentValue     = $CurrentValue
        RecommendedValue = $RecommendedValue
        Status           = $Status
        CheckId          = $subCheckId
        Remediation      = $Remediation
    })
    if ($CheckId -and (Get-Command -Name Update-CheckProgress -ErrorAction SilentlyContinue)) {
        Update-CheckProgress -CheckId $CheckId -Setting $Setting -Status $Status
    }
}

# ─── Retrieve all tenant settings ────────────────────────────────
try {
    $tenantSettings = Invoke-PowerBIRestMethod -Url 'admin/tenantSettings' -Method Get | ConvertFrom-Json
    $allSettings = $tenantSettings.tenantSettings
}
catch {
    Write-Warning "Could not retrieve Power BI tenant settings: $($_.Exception.Message)"
    $allSettings = @()
}

# Helper: look up a setting by settingName and return its isEnabled value
function Get-TenantSetting {
    param([string]$SettingName)
    $match = $allSettings | Where-Object { $_.settingName -eq $SettingName }
    if ($match) { return $match.isEnabled }
    return $null
}

# ─── CIS 9.1.1: Guest user access restricted ────────────────────
# When AllowGuestLookup is disabled, guest users cannot browse the tenant directory
$guestLookup = Get-TenantSetting -SettingName 'AllowGuestLookup'
$guestStatus = if ($guestLookup -eq $false) { 'Pass' } elseif ($null -eq $guestLookup) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Guest Access' -Setting 'Guest User Access Restricted' `
    -CurrentValue $(if ($null -eq $guestLookup) { 'Not found' } else { "$(-not $guestLookup)" }) `
    -RecommendedValue 'True' -Status $guestStatus -CheckId 'POWERBI-GUEST-001' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Export and sharing > Allow guest users to browse and access Power BI content > Disabled'

# ─── CIS 9.1.2: External user invitations restricted ────────────
$guestInvite = Get-TenantSetting -SettingName 'ElevatedGuestsTenant'
$inviteStatus = if ($guestInvite -eq $false) { 'Pass' } elseif ($null -eq $guestInvite) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Guest Access' -Setting 'External User Invitations Restricted' `
    -CurrentValue $(if ($null -eq $guestInvite) { 'Not found' } else { "$(-not $guestInvite)" }) `
    -RecommendedValue 'True' -Status $inviteStatus -CheckId 'POWERBI-GUEST-002' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Export and sharing > Invite external users to your organization > Disabled'

# ─── CIS 9.1.3: Guest access to content restricted ──────────────
$guestContent = Get-TenantSetting -SettingName 'AllowGuestUserToAccessSharedContent'
$contentStatus = if ($guestContent -eq $false) { 'Pass' } elseif ($null -eq $guestContent) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Guest Access' -Setting 'Guest Access to Content Restricted' `
    -CurrentValue $(if ($null -eq $guestContent) { 'Not found' } else { "$(-not $guestContent)" }) `
    -RecommendedValue 'True' -Status $contentStatus -CheckId 'POWERBI-GUEST-003' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Export and sharing > Allow Azure Active Directory guest users to access Power BI > Disabled'

# ─── CIS 9.1.4: Publish to web restricted ───────────────────────
$publishToWeb = Get-TenantSetting -SettingName 'WebDashboardsPublishToWebDisabled'
$publishStatus = if ($publishToWeb -eq $true) { 'Pass' } elseif ($null -eq $publishToWeb) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Sharing' -Setting 'Publish to Web Restricted' `
    -CurrentValue $(if ($null -eq $publishToWeb) { 'Not found' } else { "$publishToWeb" }) `
    -RecommendedValue 'True' -Status $publishStatus -CheckId 'POWERBI-SHARING-001' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Export and sharing > Publish to web > Disabled'

# ─── CIS 9.1.5: R and Python visuals disabled ───────────────────
$rPython = Get-TenantSetting -SettingName 'RScriptVisuals'
$rPythonStatus = if ($rPython -eq $false) { 'Pass' } elseif ($null -eq $rPython) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Sharing' -Setting 'R and Python Visuals Disabled' `
    -CurrentValue $(if ($null -eq $rPython) { 'Not found' } else { "$(-not $rPython)" }) `
    -RecommendedValue 'True' -Status $rPythonStatus -CheckId 'POWERBI-SHARING-002' `
    -Remediation 'Power BI Admin Portal > Tenant settings > R and Python visuals > Interact with and share R and Python visuals > Disabled'

# ─── CIS 9.1.6: Sensitivity labels enabled ──────────────────────
$sensitivityLabels = Get-TenantSetting -SettingName 'UseSensitivityLabels'
$labelsStatus = if ($sensitivityLabels -eq $true) { 'Pass' } elseif ($null -eq $sensitivityLabels) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Information Protection' -Setting 'Sensitivity Labels Enabled' `
    -CurrentValue $(if ($null -eq $sensitivityLabels) { 'Not found' } else { "$sensitivityLabels" }) `
    -RecommendedValue 'True' -Status $labelsStatus -CheckId 'POWERBI-INFOPROT-001' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Information protection > Allow users to apply sensitivity labels for content > Enabled'

# ─── CIS 9.1.7: Shareable links restricted ──────────────────────
$shareLinks = Get-TenantSetting -SettingName 'ShareLinkToEntireOrg'
$shareStatus = if ($shareLinks -eq $false) { 'Pass' } elseif ($null -eq $shareLinks) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Sharing' -Setting 'Shareable Links Restricted' `
    -CurrentValue $(if ($null -eq $shareLinks) { 'Not found' } else { "$(-not $shareLinks)" }) `
    -RecommendedValue 'True' -Status $shareStatus -CheckId 'POWERBI-SHARING-003' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Export and sharing > Allow shareable links to grant access to everyone in your organization > Disabled'

# ─── CIS 9.1.8: External data sharing restricted ────────────────
$extDataSharing = Get-TenantSetting -SettingName 'AllowExternalDataSharingReceiverWorksWithShare'
$extStatus = if ($extDataSharing -eq $false) { 'Pass' } elseif ($null -eq $extDataSharing) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Sharing' -Setting 'External Data Sharing Restricted' `
    -CurrentValue $(if ($null -eq $extDataSharing) { 'Not found' } else { "$(-not $extDataSharing)" }) `
    -RecommendedValue 'True' -Status $extStatus -CheckId 'POWERBI-SHARING-004' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Export and sharing > Allow external data sharing > Disabled'

# ─── CIS 9.1.9: Block ResourceKey Authentication ────────────────
$blockResKey = Get-TenantSetting -SettingName 'BlockResourceKeyAuthentication'
$resKeyStatus = if ($blockResKey -eq $true) { 'Pass' } elseif ($null -eq $blockResKey) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Authentication' -Setting 'Block ResourceKey Authentication' `
    -CurrentValue $(if ($null -eq $blockResKey) { 'Not found' } else { "$blockResKey" }) `
    -RecommendedValue 'True' -Status $resKeyStatus -CheckId 'POWERBI-AUTH-001' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Developer settings > Block ResourceKey Authentication > Enabled'

# ─── CIS 9.1.10: Service Principal API access restricted ────────
$spAccess = Get-TenantSetting -SettingName 'ServicePrincipalAccess'
$spStatus = if ($spAccess -eq $false) { 'Pass' } elseif ($null -eq $spAccess) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Authentication' -Setting 'Service Principal API Access Restricted' `
    -CurrentValue $(if ($null -eq $spAccess) { 'Not found' } else { "$(-not $spAccess)" }) `
    -RecommendedValue 'True' -Status $spStatus -CheckId 'POWERBI-AUTH-002' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Developer settings > Allow service principals to use Power BI APIs > Disabled or restricted to specific security groups'

# ─── CIS 9.1.11: Service Principal profiles restricted ──────────
$spProfiles = Get-TenantSetting -SettingName 'CreateServicePrincipalProfile'
$spProfileStatus = if ($spProfiles -eq $false) { 'Pass' } elseif ($null -eq $spProfiles) { 'Review' } else { 'Fail' }
Add-Setting -Category 'Power BI - Authentication' -Setting 'Service Principal Profiles Restricted' `
    -CurrentValue $(if ($null -eq $spProfiles) { 'Not found' } else { "$(-not $spProfiles)" }) `
    -RecommendedValue 'True' -Status $spProfileStatus -CheckId 'POWERBI-AUTH-003' `
    -Remediation 'Power BI Admin Portal > Tenant settings > Developer settings > Allow service principals to create and use profiles > Disabled'

# ─── Output ──────────────────────────────────────────────────────
$report = @($settings)
Write-Verbose "Collected $($report.Count) Power BI security configuration settings"

if ($OutputPath) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported Power BI security config ($($report.Count) settings) to $OutputPath"
}
else {
    Write-Output $report
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1 -Output Detailed"
```
Expected: All 7 tests PASS

- [ ] **Step 5: Run PSScriptAnalyzer on the new collector**

```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path PowerBI/Get-PowerBISecurityConfig.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Recurse"
```
Expected: Zero violations

- [ ] **Step 6: Commit**

```bash
git add PowerBI/Get-PowerBISecurityConfig.ps1 tests/PowerBI/Get-PowerBISecurityConfig.Tests.ps1
git commit -m "feat: add Power BI security config collector with 11 CIS 9.x checks (#66)"
```

---

### Task 2: Wire Power BI into orchestrator

**Files:**
- Modify: `Invoke-M365Assessment.ps1` (lines 89, 875-924, 929-997)
- Modify: `Common/Connect-Service.ps1` (lines 59, 90-94, 134-217)

- [ ] **Step 1: Add PowerBI to Connect-Service.ps1**

In `Common/Connect-Service.ps1`:

a. Add `'PowerBI'` to ValidateSet (line 59):
```powershell
[ValidateSet('Graph', 'ExchangeOnline', 'Purview', 'PowerBI')]
```

b. Add PowerBI to module map (after line 94):
```powershell
$moduleMap = @{
    'Graph'           = 'Microsoft.Graph.Authentication'
    'ExchangeOnline'  = 'ExchangeOnlineManagement'
    'Purview'         = 'ExchangeOnlineManagement'
    'PowerBI'         = 'MicrosoftPowerBIMgmt'
}
```

c. Add PowerBI case to the switch block (after line 216, before closing `}`):
```powershell
'PowerBI' {
    $connectParams = @{}
    if ($TenantId) { $connectParams['Tenant'] = $TenantId }

    if ($ClientId -and $CertificateThumbprint) {
        $connectParams['ServicePrincipal'] = $true
        $connectParams['ApplicationId'] = $ClientId
        $connectParams['CertificateThumbprint'] = $CertificateThumbprint
    }

    Connect-PowerBIServiceAccount @connectParams
    Write-Verbose "Connected to Power BI ($M365Environment)"
}
```

- [ ] **Step 2: Add PowerBI section to orchestrator maps**

In `Invoke-M365Assessment.ps1`:

a. Add `'PowerBI'` to ValidateSet (line 89):
```powershell
[ValidateSet('Tenant', 'Identity', 'Licensing', 'Email', 'Intune', 'Security', 'Collaboration', 'PowerBI', 'Hybrid', 'Inventory', 'ActiveDirectory', 'ScubaGear', 'SOC2')]
```

b. Add to `$sectionServiceMap` (after line 882, before `'Hybrid'`):
```powershell
'PowerBI'       = @('PowerBI')
```

c. Add to `$sectionScopeMap` (line 893 block -- PowerBI uses its own module, not Graph scopes):
```powershell
'PowerBI'       = @()
```

d. Add to `$sectionModuleMap` (line 910 block):
```powershell
'PowerBI'       = @()
```

e. Add to `$collectorMap` (after line 971 'Collaboration', before 'Hybrid'):
```powershell
'PowerBI' = @(
    @{ Name = '22-PowerBI-Security-Config'; Script = 'PowerBI\Get-PowerBISecurityConfig.ps1'; Label = 'Power BI Security Config' }
)
```

Note: Renumber existing `22-Hybrid-Sync` to `23-Hybrid-Sync` and bump subsequent numbers.

- [ ] **Step 3: Add PowerBI to default section list and wizard**

In `Invoke-M365Assessment.ps1`:

a. Update default `$Section` parameter (line 90) to include PowerBI:
```powershell
[string[]]$Section = @('Tenant', 'Identity', 'Licensing', 'Email', 'Intune', 'Security', 'Collaboration', 'PowerBI', 'Hybrid'),
```

b. Find the interactive wizard section selection menu (search for `Show-SectionMenu` or the toggle list around lines 158-433) and add PowerBI as a standard section.

- [ ] **Step 4: Run smoke tests**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/Smoke/Script-Validation.Tests.ps1 -Output Detailed"
```
Expected: All scripts parse without errors

- [ ] **Step 5: Commit**

```bash
git add Invoke-M365Assessment.ps1 Common/Connect-Service.ps1
git commit -m "feat: wire Power BI section into orchestrator and Connect-Service (#66)"
```

---

### Task 3: Update control registry for Power BI

**Files:**
- Modify: `controls/registry.json`

- [ ] **Step 1: Update the 11 MANUAL-CIS-9-1-* entries**

For each of the 11 entries, change:
- `checkId`: from `MANUAL-CIS-9-1-N` to the new checkId (`POWERBI-GUEST-001`, `POWERBI-GUEST-002`, `POWERBI-GUEST-003`, `POWERBI-SHARING-001`, `POWERBI-SHARING-002`, `POWERBI-INFOPROT-001`, `POWERBI-SHARING-003`, `POWERBI-SHARING-004`, `POWERBI-AUTH-001`, `POWERBI-AUTH-002`, `POWERBI-AUTH-003`)
- `hasAutomatedCheck`: from `false` to `true`
- `collector`: from `""` to `"PowerBI"`
- `category`: set to match (`GUEST`, `SHARING`, `INFOPROT`, `AUTH`)
- Keep `supersededBy` empty (these are not superseded, they ARE the implementation)

Mapping:
| CIS | Old CheckId | New CheckId | Category |
|-----|------------|-------------|----------|
| 9.1.1 | MANUAL-CIS-9-1-1 | POWERBI-GUEST-001 | GUEST |
| 9.1.2 | MANUAL-CIS-9-1-2 | POWERBI-GUEST-002 | GUEST |
| 9.1.3 | MANUAL-CIS-9-1-3 | POWERBI-GUEST-003 | GUEST |
| 9.1.4 | MANUAL-CIS-9-1-4 | POWERBI-SHARING-001 | SHARING |
| 9.1.5 | MANUAL-CIS-9-1-5 | POWERBI-SHARING-002 | SHARING |
| 9.1.6 | MANUAL-CIS-9-1-6 | POWERBI-INFOPROT-001 | INFOPROT |
| 9.1.7 | MANUAL-CIS-9-1-7 | POWERBI-SHARING-003 | SHARING |
| 9.1.8 | MANUAL-CIS-9-1-8 | POWERBI-SHARING-004 | SHARING |
| 9.1.9 | MANUAL-CIS-9-1-9 | POWERBI-AUTH-001 | AUTH |
| 9.1.10 | MANUAL-CIS-9-1-10 | POWERBI-AUTH-002 | AUTH |
| 9.1.11 | MANUAL-CIS-9-1-11 | POWERBI-AUTH-003 | AUTH |

- [ ] **Step 2: Verify registry integrity**

```bash
pwsh -NoProfile -Command "
$r = Get-Content controls/registry.json -Raw | ConvertFrom-Json
$pbi = $r.checks | Where-Object { $_.checkId -match '^POWERBI-' }
Write-Host \"Power BI automated checks: $($pbi.Count)\"
$pbi | ForEach-Object { Write-Host \"  $($_.checkId) automated=$($_.hasAutomatedCheck)\" }
"
```
Expected: 11 entries, all with `automated=True`

- [ ] **Step 3: Commit**

```bash
git add controls/registry.json
git commit -m "feat: update registry - 11 Power BI checks now automated (#66)"
```

---

## Chunk 2: Auth Enhancement

### Task 4: Reorder Security section collectors to minimize EXO/Purview thrashing

**Files:**
- Modify: `Invoke-M365Assessment.ps1` (lines 959-965)

- [ ] **Step 1: Reorder the Security section collectors**

Currently the Security section is ordered:
```
Secure Score (Graph) → Defender Policies (EXO) → Defender Config (EXO) → DLP (Purview) → Compliance Config (Purview)
```

This is already optimal -- EXO collectors run together, then Purview collectors run together. The thrashing happens because:
1. Security section connects EXO for Defender, then disconnects EXO for Purview (DLP/Compliance)
2. Inventory section later reconnects EXO for Mailbox/Group inventory

**Fix:** Move EXO-dependent Inventory collectors to run BEFORE Purview-dependent Security collectors. This means reordering the *sections*, not collectors within sections.

In the default `$Section` array (line 90), reorder so Inventory runs before Security's Purview collectors. Since sections run as units, the best approach is to split Security into two phases or reorder `$Section` so Inventory runs between Email and Security.

**Approach: Reorder default section execution to group EXO-dependent work together.**

Change default section order from:
```powershell
@('Tenant', 'Identity', 'Licensing', 'Email', 'Intune', 'Security', 'Collaboration', 'PowerBI', 'Hybrid')
```
to:
```powershell
@('Tenant', 'Identity', 'Licensing', 'Email', 'Intune', 'Security', 'Collaboration', 'PowerBI', 'Hybrid')
```

Actually, the current order already groups EXO collectors within Security before Purview collectors within Security. The real problem is when Inventory is also selected -- EXO gets reconnected after Purview. Since Inventory is opt-in, and Security already has per-collector RequiredServices, the thrashing only happens when both Security and Inventory are selected.

**Better fix:** When Inventory is selected, reorder it to run immediately after Email (before Security's Purview collectors kick in). This avoids the EXO→Purview→EXO cycle.

In the collector execution loop (line 1356), add logic to reorder sections for optimal connection flow:

```powershell
# Optimize section order to minimize service reconnections.
# Group all EXO-dependent sections together before Purview-dependent sections.
$sectionOrder = @(
    'Tenant', 'Identity', 'Licensing', 'Email', 'Intune',
    'Inventory',        # EXO-dependent -- run before Security's Purview collectors
    'Security',         # Graph → EXO (Defender) → Purview (DLP/Compliance)
    'Collaboration', 'PowerBI', 'Hybrid',
    'ActiveDirectory', 'ScubaGear', 'SOC2'
)
$Section = $sectionOrder | Where-Object { $_ -in $Section }
```

This ensures that when both Inventory and Security are selected, Inventory's EXO work runs before Security triggers the Purview switch.

- [ ] **Step 2: Run smoke tests**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/Smoke/Script-Validation.Tests.ps1 -Output Detailed"
```

- [ ] **Step 3: Commit**

```bash
git add Invoke-M365Assessment.ps1
git commit -m "fix: reorder sections to minimize EXO/Purview reconnection thrashing (#84)"
```

---

### Task 5: Expose ClientSecret and ManagedIdentity on orchestrator

**Files:**
- Modify: `Invoke-M365Assessment.ps1` (param block ~lines 87-130)
- Modify: `Common/Connect-Service.ps1` (param block + switch cases)

- [ ] **Step 1: Add parameters to orchestrator**

In `Invoke-M365Assessment.ps1` param block, after `$UseDeviceCode` (line 112):

```powershell
[Parameter()]
[string]$ClientSecret,

[Parameter()]
[switch]$ManagedIdentity,
```

- [ ] **Step 2: Pass new params through Connect-RequiredService**

In the `Connect-RequiredService` function (lines 1211-1228), add:

```powershell
if ($ClientSecret) { $connectParams['ClientSecret'] = $ClientSecret }
if ($ManagedIdentity) { $connectParams['ManagedIdentity'] = $true }
```

- [ ] **Step 3: Add ManagedIdentity to Connect-Service.ps1**

In `Common/Connect-Service.ps1`:

a. Add parameter (after line 81):
```powershell
[Parameter()]
[switch]$ManagedIdentity
```

b. In the Graph case (around line 136), add before the existing `if ($ClientId -and $CertificateThumbprint)`:
```powershell
if ($ManagedIdentity) {
    $connectParams['Identity'] = $true
}
elseif ($ClientId -and $CertificateThumbprint) {
```

c. In the ExchangeOnline case (around line 175), add before certificate check:
```powershell
if ($ManagedIdentity) {
    $connectParams['ManagedIdentity'] = $true
}
elseif ($ClientId -and $CertificateThumbprint) {
```

d. In the Purview case (around line 198), add a warning:
```powershell
if ($ManagedIdentity) {
    Write-Warning "Purview (Connect-IPPSSession) does not support managed identity auth. Falling back to browser-based login."
}
```

e. In the PowerBI case, add managed identity support:
```powershell
if ($ManagedIdentity) {
    # PowerBI module does not support managed identity directly
    Write-Warning "Power BI does not support managed identity auth. Use certificate-based auth instead."
}
```

- [ ] **Step 4: Run smoke tests**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/Smoke/Script-Validation.Tests.ps1 -Output Detailed"
```

- [ ] **Step 5: Commit**

```bash
git add Invoke-M365Assessment.ps1 Common/Connect-Service.ps1
git commit -m "feat: expose -ClientSecret and -ManagedIdentity auth params (#84)"
```

---

### Task 6: Update documentation

**Files:**
- Modify: `AUTHENTICATION.md`
- Modify: `docs/COMPATIBILITY.md`

- [ ] **Step 1: Update AUTHENTICATION.md**

Add sections for:
- **Client Secret** auth method with example:
  ```powershell
  .\Invoke-M365Assessment.ps1 -TenantId 'contoso.onmicrosoft.com' -ClientId '<app-id>' -ClientSecret '<secret>'
  ```
- **Managed Identity** auth method with example:
  ```powershell
  .\Invoke-M365Assessment.ps1 -ManagedIdentity
  ```
- Update the auth method support matrix to include ClientSecret and ManagedIdentity rows
- Add note about reduced auth prompts (optimal ordering)
- Document which services support which methods:

| Method | Graph | EXO | Purview | Power BI |
|--------|:-----:|:---:|:-------:|:--------:|
| Interactive | Yes | Yes | Yes | Yes |
| Device Code | Yes | Yes | No | No |
| Certificate | Yes | Yes | Yes | Yes |
| Client Secret | Yes | No | No | No |
| Managed Identity | Yes | Yes | No | No |

- [ ] **Step 2: Update COMPATIBILITY.md**

Add `MicrosoftPowerBIMgmt` to the Optional Modules table:
```markdown
| MicrosoftPowerBIMgmt | Power BI section | Required for CIS 9.x checks |
```

- [ ] **Step 3: Commit**

```bash
git add AUTHENTICATION.md docs/COMPATIBILITY.md
git commit -m "docs: update auth methods and Power BI module in compatibility matrix (#84)"
```

---

### Task 7: Update versions.md and final validation

**Files:**
- Modify: `.claude/rules/versions.md` (add PowerBI collector to list)

- [ ] **Step 1: Add PowerBI collector to versions.md**

Add to the "Security config collectors" table:
```markdown
| 18 | `PowerBI/Get-PowerBISecurityConfig.ps1` |
```

Renumber subsequent entries (18→19, 19→20, etc.).

- [ ] **Step 2: Run full test suite**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/ -Output Detailed"
```
Expected: All tests pass (smoke + Entra + PowerBI)

- [ ] **Step 3: Run PSScriptAnalyzer on all changed files**

```bash
pwsh -NoProfile -Command "
@('PowerBI/Get-PowerBISecurityConfig.ps1', 'Invoke-M365Assessment.ps1', 'Common/Connect-Service.ps1') | ForEach-Object {
    Invoke-ScriptAnalyzer -Path $_ -Settings PSScriptAnalyzerSettings.psd1
}
"
```
Expected: Zero violations

- [ ] **Step 4: Commit versions.md**

```bash
git add .claude/rules/versions.md
git commit -m "chore: add PowerBI collector to version tracking (#66)"
```

- [ ] **Step 5: Create PR**

```bash
gh pr create --title "feat: Power BI collector + auth enhancement (v0.9.0)" --body "$(cat <<'EOF'
## Summary
- Add Power BI security config collector with 11 CIS 9.1.x checks (#66)
- Expose -ClientSecret and -ManagedIdentity auth parameters (#84)
- Reorder section execution to minimize EXO/Purview reconnection prompts (#84)
- Update control registry: 11 Power BI checks now automated
- Update AUTHENTICATION.md and COMPATIBILITY.md

## CIS Coverage
- Before: 126/129 automated (97.7%)
- After: 129/129 automated (100% of automatable controls)
- 3 permanently manual controls documented with API gap notes

## Test plan
- [ ] `Invoke-Pester tests/ -Output Detailed` -- all tests pass
- [ ] PSScriptAnalyzer clean on all changed files
- [ ] CI pipeline passes (lint + test + version-check jobs)
- [ ] Live test: `.\Invoke-M365Assessment.ps1 -Section PowerBI` against test tenant
- [ ] Live test: Full run verifies reduced auth prompts

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
