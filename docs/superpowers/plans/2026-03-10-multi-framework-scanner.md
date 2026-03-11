# Multi-Framework Security Scanner Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform M365-Assess from a CIS-focused scanner into a multi-framework security assessment platform with native SOC 2 support as the first new framework.

**Architecture:** Data-driven inversion — a JSON control registry becomes the single source of truth for all check-to-framework mappings. Collectors emit framework-agnostic CheckIds. The report layer loads framework profiles dynamically and renders native views per framework.

**Tech Stack:** PowerShell 7.x, JSON (registry/profiles), HTML/CSS/JS (report), Pester 5.x (tests)

**Spec:** `docs/superpowers/specs/2026-03-10-multi-framework-scanner-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `controls/registry.json` | Master control registry — every check with framework mappings, licensing |
| `controls/frameworks/cis-m365-v6.json` | CIS framework profile — grouping, scoring, CIS-specific metadata |
| `controls/frameworks/soc2-tsc.json` | SOC 2 framework profile — CC criteria grouping, licensing profiles |
| `Common/Import-ControlRegistry.ps1` | Helper to load registry.json + framework profiles at report time |
| `tests/Common/Import-ControlRegistry.Tests.ps1` | Pester tests for registry loader |
| `tests/controls/registry-integrity.Tests.ps1` | Pester tests validating registry data integrity |

### Modified Files
| File | What Changes |
|------|-------------|
| `Entra/Get-EntraSecurityConfig.ps1` | `Add-Setting` param rename + all call sites: `-CisControl` → `-CheckId` |
| `Exchange-Online/Get-ExoSecurityConfig.ps1` | Same |
| `Security/Get-DefenderSecurityConfig.ps1` | Same |
| `Collaboration/Get-SharePointSecurityConfig.ps1` | Same |
| `Collaboration/Get-TeamsSecurityConfig.ps1` | Same |
| `Common/Export-AssessmentReport.ps1` | Load registry, key on CheckId, dynamic framework loading, SOC 2 view |

### Retired Files (after migration)
| File | Replaced By |
|------|------------|
| `Common/framework-mappings.csv` | `controls/registry.json` (CSV kept as generated export if needed) |

---

## Chunk 1: Control Registry + Loader

### Task 1: Build CheckId mapping table

Map every existing CIS control to its new CheckId. This is a reference table used by all
subsequent tasks.

**Files:**
- Create: `controls/check-id-mapping.csv` (temporary reference, used during migration)

- [ ] **Step 1: Create the CheckId mapping CSV**

Build a CSV that maps every CIS control ID to its new CheckId, using the convention
`{COLLECTOR}-{AREA}-{NNN}`. Source data from the 5 collectors' Add-Setting calls.

The mapping must cover all unique CIS control IDs found in the collectors:

Entra (12 call sites, 10 unique CIS IDs): 1.1.3, 5.1.5.1, 5.1.3.2, 5.1.2.3,
5.1.5.2, 5.2.3.4, 5.2.3.2, 1.3.1, 5.1.6.3, 5.1.6.2

EXO (14 call sites, 10 unique CIS IDs): 6.5.1, 6.1.1, 1.3.6, 6.5.2, 6.2.3, 6.2.1,
6.5.3, 1.3.3, 6.1.3, 6.5.4

Defender (31 call sites, 8 unique CIS IDs): 2.1.7, 2.1.6, 2.1.2, 2.1.3, 2.1.1,
2.1.4, 6.2.1, 2.1.15

SharePoint (12 call sites, 9 unique CIS IDs): 7.2.3, 7.2.5, 7.2.6, 7.3.2, 1.3.2,
7.2.7, 7.2.9, 7.2.10, 7.2.11

Teams (7 call sites, 7 unique CIS IDs): 8.2.2, 8.2.3, 8.5.1, 8.5.2, 8.5.3, 8.5.4,
8.5.7

**Important:** Verify these counts against the actual codebase before starting. Use:
```bash
pwsh -NoProfile -Command "Select-String -Path 'Entra/*.ps1','Exchange-Online/*.ps1','Security/*.ps1','Collaboration/*.ps1' -Pattern '-CisControl' | Group-Object Path | Select-Object Name, Count"
```

Format:
```csv
CisControl,CheckId,Collector,Area
1.1.3,ENTRA-ADMIN-001,Entra,Admin Accounts
5.1.2.3,ENTRA-MFA-001,Entra,MFA
...
```

Note: Some CIS controls appear in multiple Add-Setting calls within the same collector
(e.g., 2.1.7 appears 7 times in Defender for different anti-phishing sub-settings).
Multiple Add-Setting calls sharing the same CIS control should share the same CheckId —
they represent sub-checks of one logical control.

- [ ] **Step 2: Verify completeness**

Run a quick count to verify the mapping covers all unique CIS control IDs across all 5
collectors. Cross-reference against `Common/framework-mappings.csv` which has 140 rows.

Note: The 5 security config collectors only cover a subset of the 140 CIS controls (~45
unique). The remaining ~95 controls in framework-mappings.csv do not have corresponding
automated checks — they exist only as framework mapping metadata. The registry should
include entries for all 140, with a `"hasAutomatedCheck": false` flag for unmapped ones.

- [ ] **Step 3: Commit**

```bash
git add controls/check-id-mapping.csv
git commit -m "chore: add CheckId mapping table for CIS-to-CheckId migration"
```

---

### Task 2: Create the control registry (registry.json)

Transform `Common/framework-mappings.csv` into `controls/registry.json` with the new
CheckId-based structure.

**Files:**
- Create: `controls/registry.json`
- Read: `Common/framework-mappings.csv` (source data)
- Read: `controls/check-id-mapping.csv` (from Task 1)

- [ ] **Step 1: Write a PowerShell conversion script**

Create a temporary script `_build-registry.ps1` that:
1. Reads `Common/framework-mappings.csv` (140 rows)
2. Reads `controls/check-id-mapping.csv` (from Task 1)
3. For each CIS control, builds a registry entry:

```json
{
  "checks": [
    {
      "checkId": "ENTRA-ADMIN-001",
      "name": "Global Administrator Count",
      "category": "Admin Accounts",
      "collector": "Entra",
      "hasAutomatedCheck": true,
      "licensing": { "minimum": "E3" },
      "frameworks": {
        "cis-m365-v6": {
          "controlId": "1.1.3",
          "title": "Ensure that between two and four global admins are designated",
          "profiles": ["E3-L1", "E5-L1"]
        },
        "nist-csf": { "controlId": "PR.AA-05" },
        "nist-800-53": { "controlId": "AC-6(5)" },
        "iso-27001": { "controlId": "A.5.15;A.8.2" },
        "stig": { "controlId": "V-260335" },
        "pci-dss": { "controlId": "8.2.x" },
        "cmmc": { "controlId": "3.1.5;3.1.6" },
        "hipaa": { "controlId": "§164.312(a)(1);§164.308(a)(4)(i)" },
        "cisa-scuba": { "controlId": "MS.AAD.7.1v1" }
      }
    }
  ]
}
```

The `frameworks` object keys match the existing framework-mappings.csv column names
(lowercased/kebab-cased). CIS profiles (E3-L1, E3-L2, E5-L1, E5-L2) are derived from
the CisE3L1/CisE3L2/CisE5L1/CisE5L2 columns — if the column has a value, the control
belongs to that profile.

For the ~95 controls without automated checks, set `"hasAutomatedCheck": false` and use
a placeholder CheckId pattern like `MANUAL-CIS-{controlId}`.

- [ ] **Step 2: Run the conversion and validate**

```powershell
pwsh -NoProfile -File _build-registry.ps1
```

Validate the output:
- Total entries = 140 (matching framework-mappings.csv)
- Entries with `hasAutomatedCheck: true` ≈ 45 (matching collector coverage)
- Every entry has at least a `cis-m365-v6` framework mapping
- JSON is valid (test with `Get-Content controls/registry.json | ConvertFrom-Json`)

- [ ] **Step 3: Add SOC 2 mappings to the registry**

For each check entry, add a `"soc2"` key to the `frameworks` object. Use the mapping
chain:
- CIS control → NIST 800-53 control (already in registry) → SOC 2 CC criteria

Primary CC criteria mappings for M365-relevant checks:

| NIST 800-53 Family | SOC 2 CC Criteria |
|-------------------|-------------------|
| AC (Access Control) | CC6.1, CC6.2, CC6.3 |
| AU (Audit) | CC7.1, CC7.2 |
| IA (Identification/Auth) | CC6.1 |
| CM (Configuration Mgmt) | CC5.2, CC8.1 |
| SC (System/Comms Protection) | CC6.1, CC6.7 |
| SI (System/Info Integrity) | CC6.8, CC7.1 |

Example addition to an existing entry:
```json
"soc2": { "controlId": "CC6.1;CC6.3", "evidenceType": "config-export" }
```

Cross-validate against the A-Lign SOC 2 Requirements spreadsheet
(`C:\Users\Daren\Downloads\A-Lign SOC2 Requirements.xlsx`) — check that the CC criteria
in the registry align with what the auditor actually asks for.

- [ ] **Step 4: Keep build script and commit**

Move the conversion script to `controls/Build-Registry.ps1` (tracked, not temporary).
This script is needed whenever the registry must be regenerated (e.g., when CIS publishes
a new benchmark version or new controls are added).

```bash
git add controls/registry.json controls/Build-Registry.ps1
git commit -m "feat: create control registry with all framework mappings including SOC 2"
```

---

### Task 3: Create the registry loader helper

Build the PowerShell helper that loads `registry.json` and framework profiles at report
time.

**Files:**
- Create: `Common/Import-ControlRegistry.ps1`
- Create: `tests/Common/Import-ControlRegistry.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/Common/Import-ControlRegistry.Tests.ps1
Describe 'Import-ControlRegistry' {
    BeforeAll {
        . "$PSScriptRoot/../../Common/Import-ControlRegistry.ps1"
        $testRoot = "$PSScriptRoot/../../controls"
    }

    It 'Returns a hashtable keyed by CheckId' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $registry | Should -BeOfType [hashtable]
        $registry.Keys | Should -Contain 'ENTRA-ADMIN-001'
    }

    It 'Each entry contains frameworks object' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $entry = $registry['ENTRA-ADMIN-001']
        $entry.frameworks | Should -Not -BeNullOrEmpty
        $entry.frameworks.'cis-m365-v6'.controlId | Should -Not -BeNullOrEmpty
    }

    It 'Builds a reverse lookup from CIS control ID to CheckId' {
        $registry = Import-ControlRegistry -ControlsPath $testRoot
        $reverseLookup = $registry['__cisReverseLookup']
        $reverseLookup['1.1.3'] | Should -Not -BeNullOrEmpty
        $reverseLookup['1.1.3'] | Should -Match '^[A-Z]+-[A-Z]+-\d{3}$'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/Common/Import-ControlRegistry.Tests.ps1 -Output Detailed"
```

Expected: FAIL — function not found.

- [ ] **Step 3: Implement Import-ControlRegistry.ps1**

```powershell
# Common/Import-ControlRegistry.ps1
<#
.SYNOPSIS
    Loads the control registry and builds lookup tables for the report layer.
.DESCRIPTION
    Reads controls/registry.json and returns a hashtable keyed by CheckId.
    Also builds a reverse lookup from CIS control IDs to CheckIds (stored
    under the special key '__cisReverseLookup') for backward compatibility
    with CSVs that still use the CisControl column.
.PARAMETER ControlsPath
    Path to the controls/ directory containing registry.json.
.OUTPUTS
    [hashtable] — Keys are CheckIds, values are registry entry objects.
    Special key '__cisReverseLookup' maps CIS control IDs to CheckIds.
#>
function Import-ControlRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ControlsPath
    )

    $registryPath = Join-Path -Path $ControlsPath -ChildPath 'registry.json'
    if (-not (Test-Path -Path $registryPath)) {
        Write-Warning "Control registry not found: $registryPath"
        return @{}
    }

    $raw = Get-Content -Path $registryPath -Raw | ConvertFrom-Json
    $lookup = @{}
    $cisReverse = @{}

    foreach ($check in $raw.checks) {
        $entry = @{
            checkId           = $check.checkId
            name              = $check.name
            category          = $check.category
            collector         = $check.collector
            hasAutomatedCheck = $check.hasAutomatedCheck
            licensing         = $check.licensing
            frameworks        = @{}
        }

        # Convert framework PSCustomObject properties to hashtable
        foreach ($prop in $check.frameworks.PSObject.Properties) {
            $entry.frameworks[$prop.Name] = $prop.Value
        }

        $lookup[$check.checkId] = $entry

        # Build CIS reverse lookup
        $cisMapping = $check.frameworks.'cis-m365-v6'
        if ($cisMapping -and $cisMapping.controlId) {
            $cisReverse[$cisMapping.controlId] = $check.checkId
        }
    }

    $lookup['__cisReverseLookup'] = $cisReverse
    return $lookup
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/Common/Import-ControlRegistry.Tests.ps1 -Output Detailed"
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Common/Import-ControlRegistry.ps1 tests/Common/Import-ControlRegistry.Tests.ps1
git commit -m "feat: add Import-ControlRegistry helper with CIS reverse lookup"
```

---

### Task 4: Create framework profile JSONs

Build the CIS and SOC 2 framework profiles that define grouping, scoring, and display
metadata.

**Files:**
- Create: `controls/frameworks/cis-m365-v6.json`
- Create: `controls/frameworks/soc2-tsc.json`

- [ ] **Step 1: Create CIS framework profile**

This profile preserves the existing CIS report behavior — 4 licensing profiles, section-
based grouping derived from control ID prefixes.

```json
{
  "frameworkId": "cis-m365-v6",
  "label": "CIS Microsoft 365 v6.0.1",
  "version": "6.0.1",
  "css": "fw-cis",
  "totalControls": 140,
  "scoring": {
    "method": "profile-compliance",
    "profiles": {
      "E3-L1": { "label": "CIS E3 Level 1", "css": "fw-cis", "profileKey": "E3-L1" },
      "E3-L2": { "label": "CIS E3 Level 2", "css": "fw-cis-l2", "profileKey": "E3-L2" },
      "E5-L1": { "label": "CIS E5 Level 1", "css": "fw-cis", "profileKey": "E5-L1" },
      "E5-L2": { "label": "CIS E5 Level 2", "css": "fw-cis-l2", "profileKey": "E5-L2" }
    }
  },
  "groupBy": "section-prefix",
  "sections": {
    "1": "Identity",
    "2": "Defender",
    "3": "Purview",
    "5": "Entra ID",
    "6": "Exchange Online",
    "7": "SharePoint & OneDrive",
    "8": "Teams"
  }
}
```

- [ ] **Step 2: Create SOC 2 framework profile**

```json
{
  "frameworkId": "soc2-tsc",
  "label": "SOC 2 Trust Services Criteria",
  "version": "2022",
  "css": "fw-soc2",
  "scoring": {
    "method": "criteria-coverage",
    "criteria": {
      "CC5": {
        "label": "Control Activities",
        "description": "Security policies and procedures are in place and operating effectively"
      },
      "CC6.1": {
        "label": "Logical & Physical Access — Authentication",
        "description": "Access to systems and data is restricted through authentication mechanisms"
      },
      "CC6.2": {
        "label": "Logical & Physical Access — Provisioning",
        "description": "Access is granted, modified, and removed in a timely manner"
      },
      "CC6.3": {
        "label": "Logical & Physical Access — Authorization",
        "description": "Role-based access with least privilege enforcement"
      },
      "CC6.5": {
        "label": "Logical & Physical Access — Revocation",
        "description": "Access is revoked when no longer appropriate"
      },
      "CC6.6": {
        "label": "System Boundaries — External Threats",
        "description": "Systems are protected against external threats"
      },
      "CC6.7": {
        "label": "System Boundaries — Data Protection",
        "description": "Data transmission and storage is restricted and protected"
      },
      "CC6.8": {
        "label": "System Boundaries — Malware Prevention",
        "description": "Unauthorized and malicious software is prevented or detected"
      },
      "CC7.1": {
        "label": "System Operations — Monitoring",
        "description": "Security events are monitored and anomalies are detected"
      },
      "CC7.2": {
        "label": "System Operations — Anomaly Detection",
        "description": "Anomalies are evaluated to determine if they represent security events"
      },
      "CC8.1": {
        "label": "Change Management",
        "description": "Changes to infrastructure and software are authorized and managed"
      }
    }
  },
  "licensingProfiles": {
    "E3": {
      "label": "Microsoft 365 E3",
      "excludeChecks": ["ENTRA-PIM-001", "ENTRA-IDRISK-001", "ENTRA-USERRISK-001"]
    },
    "E5": {
      "label": "Microsoft 365 E5",
      "excludeChecks": []
    }
  },
  "nonAutomatableCriteria": {
    "CC1": { "label": "Control Environment", "note": "Requires organizational governance documentation" },
    "CC2": { "label": "Communication & Information", "note": "Requires policy documentation review" },
    "CC3": { "label": "Risk Assessment", "note": "Partially automatable via Secure Score (Phase 2)" },
    "CC4": { "label": "Monitoring Activities", "note": "Partially automatable via Compliance Manager" },
    "CC9": { "label": "Risk Mitigation", "note": "Requires vendor management and business continuity review" }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add controls/frameworks/cis-m365-v6.json controls/frameworks/soc2-tsc.json
git commit -m "feat: add CIS and SOC 2 framework profile definitions"
```

---

### Task 5: Registry integrity tests

Write Pester tests that validate registry.json data integrity — ensuring all CheckIds
are unique, all framework references are valid, and the CIS migration is complete.

**Files:**
- Create: `tests/controls/registry-integrity.Tests.ps1`

- [ ] **Step 1: Write integrity tests**

```powershell
# tests/controls/registry-integrity.Tests.ps1
Describe 'Control Registry Integrity' {
    BeforeAll {
        $registryPath = "$PSScriptRoot/../../controls/registry.json"
        $raw = Get-Content -Path $registryPath -Raw | ConvertFrom-Json
        $checks = $raw.checks
    }

    It 'Has at least 140 entries (matching CIS benchmark count)' {
        $checks.Count | Should -BeGreaterOrEqual 140
    }

    It 'Has no duplicate CheckIds' {
        $ids = $checks | ForEach-Object { $_.checkId }
        $dupes = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
        $dupes | Should -BeNullOrEmpty -Because "CheckIds must be unique"
    }

    It 'Every entry has required fields' {
        foreach ($check in $checks) {
            $check.checkId | Should -Not -BeNullOrEmpty
            $check.name | Should -Not -BeNullOrEmpty
            $check.frameworks | Should -Not -BeNullOrEmpty
            $check.frameworks.'cis-m365-v6' | Should -Not -BeNullOrEmpty `
                -Because "$($check.checkId) must have CIS mapping"
        }
    }

    It 'All automated checks have a collector field' {
        $automated = $checks | Where-Object { $_.hasAutomatedCheck -eq $true }
        foreach ($check in $automated) {
            $check.collector | Should -Not -BeNullOrEmpty `
                -Because "$($check.checkId) is automated and needs a collector"
        }
    }

    It 'CheckId format matches convention {COLLECTOR}-{AREA}-{NNN}' {
        $automated = $checks | Where-Object { $_.hasAutomatedCheck -eq $true }
        foreach ($check in $automated) {
            $check.checkId | Should -Match '^[A-Z]+-[A-Z]+-\d{3}$' `
                -Because "$($check.checkId) must follow naming convention"
        }
    }

    It 'SOC 2 mappings exist for checks that have NIST 800-53 AC/AU/IA/SC/SI families' {
        $nistFamilies = @('AC-', 'AU-', 'IA-', 'SC-', 'SI-')
        $automated = $checks | Where-Object { $_.hasAutomatedCheck -eq $true }
        foreach ($check in $automated) {
            $nist = $check.frameworks.'nist-800-53'
            if ($nist -and $nist.controlId) {
                $matchesFamily = $nistFamilies | Where-Object {
                    $nist.controlId -like "$_*"
                }
                if ($matchesFamily) {
                    $check.frameworks.soc2 | Should -Not -BeNullOrEmpty `
                        -Because "$($check.checkId) maps to NIST $($nist.controlId) which should have SOC 2 mapping"
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/controls/registry-integrity.Tests.ps1 -Output Detailed"
```

Expected: All tests PASS (assuming registry.json from Task 2 is complete).

- [ ] **Step 3: Commit**

```bash
git add tests/controls/registry-integrity.Tests.ps1
git commit -m "test: add registry integrity validation tests"
```

---

## Chunk 2: Collector Migration

> **WARNING: Broken state during migration.** Tasks 6-10 change collector output from
> `CisControl` to `CheckId`, but the report layer (Task 11) still expects `CisControl`.
> Between Tasks 6 and 11, the report's compliance matrix will be empty for migrated
> collectors. **Do not run the full assessment or merge to main until Task 11 is
> complete.** All of Chunk 2 + Chunk 3 should be on a feature branch and merged together.

### Task 6: Migrate Entra collector to CheckId

**Files:**
- Modify: `Entra/Get-EntraSecurityConfig.ps1` (lines 58-77 for Add-Setting def, ~12 call sites)
- Read: `controls/check-id-mapping.csv` (reference)

- [ ] **Step 1: Update Add-Setting function definition**

In `Entra/Get-EntraSecurityConfig.ps1`, change the `Add-Setting` function (lines 58-77):

Replace parameter `-CisControl` (line 65):
```powershell
# Before (line 65):
[string]$CisControl = ''

# After:
[string]$CheckId = ''
```

Replace the PSCustomObject property in the function body:
```powershell
# Before:
CisControl       = $CisControl

# After:
CheckId          = $CheckId
```

- [ ] **Step 2: Update all Add-Setting call sites**

Replace every `-CisControl '...'` with the corresponding `-CheckId '...'` using the
mapping from Task 1. There are ~12 Add-Setting calls in this file. Verify the exact
count before starting.

Example:
```powershell
# Before:
-CisControl '1.1.3'
# After:
-CheckId 'ENTRA-ADMIN-001'
```

- [ ] **Step 3: Verify syntax**

```bash
pwsh -NoProfile -Command "& { $null = [System.Management.Automation.Language.Parser]::ParseFile('Entra/Get-EntraSecurityConfig.ps1', [ref]$null, [ref]$null) ; Write-Host 'Parse OK' }"
```

Expected: "Parse OK"

- [ ] **Step 4: Commit**

```bash
git add Entra/Get-EntraSecurityConfig.ps1
git commit -m "refactor(entra): migrate Add-Setting from CisControl to CheckId"
```

---

### Task 7: Migrate Exchange Online collector to CheckId

**Files:**
- Modify: `Exchange-Online/Get-ExoSecurityConfig.ps1` (lines 35-54 for Add-Setting def, ~14 call sites)

- [ ] **Step 1: Update Add-Setting function definition**

Same pattern as Task 6: rename `-CisControl` parameter (line 42) to `-CheckId`, update
PSCustomObject property.

- [ ] **Step 2: Update all Add-Setting call sites**

Replace all ~14 `-CisControl '...'` with corresponding `-CheckId '...'` values from the
mapping. Verify exact count before starting.

- [ ] **Step 3: Verify syntax**

```bash
pwsh -NoProfile -Command "& { $null = [System.Management.Automation.Language.Parser]::ParseFile('Exchange-Online/Get-ExoSecurityConfig.ps1', [ref]$null, [ref]$null) ; Write-Host 'Parse OK' }"
```

- [ ] **Step 4: Commit**

```bash
git add Exchange-Online/Get-ExoSecurityConfig.ps1
git commit -m "refactor(exo): migrate Add-Setting from CisControl to CheckId"
```

---

### Task 8: Migrate Defender collector to CheckId

**Files:**
- Modify: `Security/Get-DefenderSecurityConfig.ps1` (lines 44-63 for Add-Setting def, ~31 call sites)

This is the largest collector — ~31 Add-Setting calls. Many share the same CIS control ID
(e.g., 2.1.7 appears 7 times for different anti-phishing sub-settings). All calls sharing
a CIS control ID get the same CheckId.

- [ ] **Step 1: Update Add-Setting function definition**

Same pattern: rename `-CisControl` (line 51) to `-CheckId`, update PSCustomObject.

- [ ] **Step 2: Update all Add-Setting call sites**

Replace all ~31 `-CisControl '...'` with corresponding `-CheckId '...'` values.
Verify exact count before starting.

- [ ] **Step 3: Verify syntax**

```bash
pwsh -NoProfile -Command "& { $null = [System.Management.Automation.Language.Parser]::ParseFile('Security/Get-DefenderSecurityConfig.ps1', [ref]$null, [ref]$null) ; Write-Host 'Parse OK' }"
```

- [ ] **Step 4: Commit**

```bash
git add Security/Get-DefenderSecurityConfig.ps1
git commit -m "refactor(defender): migrate Add-Setting from CisControl to CheckId"
```

---

### Task 9: Migrate SharePoint collector to CheckId

**Files:**
- Modify: `Collaboration/Get-SharePointSecurityConfig.ps1` (lines 52-71, ~12 call sites)

- [ ] **Step 1-4: Same pattern as Tasks 6-8**

Update function def (line 59), update ~12 call sites, verify syntax, commit.

```bash
git add Collaboration/Get-SharePointSecurityConfig.ps1
git commit -m "refactor(sharepoint): migrate Add-Setting from CisControl to CheckId"
```

---

### Task 10: Migrate Teams collector to CheckId

**Files:**
- Modify: `Collaboration/Get-TeamsSecurityConfig.ps1` (lines 49-68, ~7 call sites)

- [ ] **Step 1-4: Same pattern as Tasks 6-8**

Update function def (line 56), update ~7 call sites, verify syntax, commit.

```bash
git add Collaboration/Get-TeamsSecurityConfig.ps1
git commit -m "refactor(teams): migrate Add-Setting from CisControl to CheckId"
```

---

## Chunk 3: Report Layer Migration

### Task 11: Update report to load registry and key on CheckId

This is the largest and most critical task. The report layer must switch from
`framework-mappings.csv` keyed on `CisControl` to `registry.json` keyed on `CheckId`.

**Files:**
- Modify: `Common/Export-AssessmentReport.ps1` (multiple locations)
- Read: `Common/Import-ControlRegistry.ps1` (from Task 3)

- [ ] **Step 1: Add registry loading at report startup**

At the top of Export-AssessmentReport.ps1 (after line 78, after `$cisProfileKeys`),
add registry loading:

```powershell
# Load control registry
. (Join-Path -Path $PSScriptRoot -ChildPath 'Import-ControlRegistry.ps1')
$controlsPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'controls'
$controlRegistry = Import-ControlRegistry -ControlsPath $controlsPath
$cisReverseLookup = if ($controlRegistry.ContainsKey('__cisReverseLookup')) {
    $controlRegistry['__cisReverseLookup']
} else { @{} }
```

- [ ] **Step 2: Replace framework-mappings.csv loading with registry-based lookup**

At lines 124-130, replace the CSV-based framework mappings load:

```powershell
# Before (lines 124-130):
$mappingsPath = Join-Path -Path $PSScriptRoot -ChildPath 'framework-mappings.csv'
# ... CSV loading logic ...

# After:
# Build $frameworkMappings from registry for backward compatibility
# This creates the same hashtable structure the rest of the report expects
$frameworkMappings = @{}
foreach ($key in $controlRegistry.Keys) {
    if ($key -eq '__cisReverseLookup') { continue }
    $entry = $controlRegistry[$key]
    $cisId = $entry.frameworks.'cis-m365-v6'.controlId
    if ($cisId) {
        $mappingRow = [PSCustomObject]@{
            CisControl = $cisId
            CisTitle   = $entry.name
        }
        # Add all framework columns dynamically
        foreach ($fwKey in $entry.frameworks.Keys) {
            $fwConfig = $entry.frameworks[$fwKey]
            if ($fwConfig.controlId) {
                $mappingRow | Add-Member -NotePropertyName $fwKey -NotePropertyValue $fwConfig.controlId -Force
            }
        }
        # Add CIS profile columns
        $cisProfiles = $entry.frameworks.'cis-m365-v6'.profiles
        if ($cisProfiles) {
            foreach ($profile in @('E3-L1','E3-L2','E5-L1','E5-L2')) {
                $colName = "Cis$($profile -replace '-','')"
                $val = if ($cisProfiles -contains $profile) { $cisId } else { '' }
                $mappingRow | Add-Member -NotePropertyName $colName -NotePropertyValue $val -Force
            }
        }
        $frameworkMappings[$cisId] = $mappingRow
    }
}
```

- [ ] **Step 3: Update CisControl column detection to also handle CheckId**

At lines 371, 1225, 1582 — everywhere the report checks for `CisControl` column — add
CheckId support:

```powershell
# Before (line 371):
if ($columns -contains 'Status' -and $columns -contains 'CisControl')

# After:
if ($columns -contains 'Status' -and ($columns -contains 'CheckId' -or $columns -contains 'CisControl'))
```

```powershell
# Before (line 1225):
$isSecurityConfig = ($columns -contains 'CisControl') -and ($columns -contains 'Status')

# After:
$isSecurityConfig = ($columns -contains 'CheckId' -or $columns -contains 'CisControl') -and ($columns -contains 'Status')
```

```powershell
# Before (line 1582):
if ($columns -notcontains 'CisControl') { continue }

# After:
if ($columns -notcontains 'CheckId' -and $columns -notcontains 'CisControl') { continue }
```

- [ ] **Step 4: Update the finding extraction loop to resolve CheckId → CIS control**

At lines 1585-1588, update the logic to handle both column types:

```powershell
# Before:
if (-not $row.CisControl -or $row.CisControl -eq '') { continue }
$mapping = if ($frameworkMappings.ContainsKey($row.CisControl)) { ... }
# ... and later at line 1588:
# CisControl = $row.CisControl

# After:
$cisId = $null
$checkId = $null
if ($columns -contains 'CheckId' -and $row.CheckId) {
    # New format: look up CIS control via registry
    $checkId = $row.CheckId
    $regEntry = if ($controlRegistry.ContainsKey($checkId)) { $controlRegistry[$checkId] } else { $null }
    $cisId = if ($regEntry) { $regEntry.frameworks.'cis-m365-v6'.controlId } else { $null }
} elseif ($columns -contains 'CisControl' -and $row.CisControl) {
    # Legacy format: use CisControl directly
    $cisId = $row.CisControl
}
if (-not $cisId) { continue }
$mapping = if ($frameworkMappings.ContainsKey($cisId)) { $frameworkMappings[$cisId] } else { $null }
```

**CRITICAL:** Also update line 1588 where the finding object is built. Change:
```powershell
CisControl = $row.CisControl
```
to:
```powershell
CisControl = $cisId
```

Without this change, the compliance matrix will be empty because `$row.CisControl` no
longer exists in CheckId-based CSVs. The `$cisId` variable (resolved via registry
lookup) must be used instead. Lines 1755 (`Sort-Object -Property CisControl`) and
1765 (`$finding.CisControl`) are downstream of this and will work correctly once
line 1588 is fixed.

- [ ] **Step 5: Replace static $frameworkLookup with dynamic loading from framework profiles**

Per the spec, adding a framework must not require code changes. Replace the hardcoded
`$frameworkLookup` and `$allFrameworkKeys` (lines 62-78) with dynamic loading:

```powershell
# Load framework display metadata dynamically from profile JSONs
$frameworkProfileDir = Join-Path -Path $controlsPath -ChildPath 'frameworks'
$frameworkLookup = [ordered]@{}
$allFrameworkKeys = @()

# CIS profiles are special — 4 sub-profiles from one framework file
$cisProfile = Join-Path -Path $frameworkProfileDir -ChildPath 'cis-m365-v6.json'
if (Test-Path $cisProfile) {
    $cis = Get-Content $cisProfile -Raw | ConvertFrom-Json
    foreach ($profileKey in $cis.scoring.profiles.PSObject.Properties.Name) {
        $p = $cis.scoring.profiles.$profileKey
        $fwKey = "CIS-$profileKey" -replace 'L(\d)','L$1'
        $frameworkLookup[$fwKey] = @{
            Col   = "Cis$($profileKey -replace '-','')"
            Label = $p.label
            Css   = $p.css
        }
        $allFrameworkKeys += $fwKey
    }
}

# All other framework profiles
$otherProfiles = Get-ChildItem -Path $frameworkProfileDir -Filter '*.json' |
    Where-Object { $_.Name -ne 'cis-m365-v6.json' }
foreach ($profileFile in $otherProfiles) {
    $fw = Get-Content $profileFile.FullName -Raw | ConvertFrom-Json
    $fwKey = $fw.frameworkId.ToUpper() -replace '-',' ' -replace ' ','-'
    $frameworkLookup[$fwKey] = @{
        Col   = $fw.frameworkId -replace '-',''
        Label = $fw.label
        Css   = $fw.css
    }
    $allFrameworkKeys += $fwKey
}

$cisProfileKeys = @($allFrameworkKeys | Where-Object { $_ -like 'CIS-*' })
```

**Note:** The `Col` value for each framework must match the property names used when
building `$frameworkMappings` from the registry (Task 11 Step 2). The registry uses
framework keys like `soc2`, `nist-800-53`, etc. — the `Col` value should be the
framework key with hyphens removed (e.g., `soc2`, `nist80053`) to match the existing
column-name convention. Verify alignment after implementing.

- [ ] **Step 6: Add SOC 2 CSS colors**

At line 3127 (after `.fw-scuba`), add light theme:
```css
.fw-soc2  { background: #eff6ff; color: #1e3a5f; }
```

At line 3206 (after `.dark-theme .fw-scuba`), add dark theme:
```css
body.dark-theme .fw-soc2   { background: #1E3A5F; color: #93B5CF; }
```

- [ ] **Step 7: Verify syntax**

```bash
pwsh -NoProfile -Command "& { $null = [System.Management.Automation.Language.Parser]::ParseFile('Common/Export-AssessmentReport.ps1', [ref]$null, [ref]$null) ; Write-Host 'Parse OK' }"
```

- [ ] **Step 8: Commit**

```bash
git add Common/Export-AssessmentReport.ps1
git commit -m "feat(report): load control registry, support CheckId column, add SOC 2 framework"
```

---

### Task 12: Smoke test the full pipeline

Run the assessment (or simulate it) to verify the report generates correctly with the
new registry-based pipeline.

**Files:**
- Read: All modified files from Tasks 6-11

- [ ] **Step 1: Verify all Pester tests pass**

```bash
pwsh -NoProfile -Command "Invoke-Pester tests/ -Output Detailed"
```

Expected: All tests pass.

- [ ] **Step 2: Run PSScriptAnalyzer on modified files**

```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path Common/Export-AssessmentReport.ps1 -Severity Error,Warning"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path Common/Import-ControlRegistry.ps1 -Severity Error,Warning"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path Entra/Get-EntraSecurityConfig.ps1 -Severity Error,Warning"
```

Expected: No errors or warnings on the modified code.

- [ ] **Step 3: Verify Get-Help works for modified scripts**

```bash
pwsh -NoProfile -Command "Get-Help ./Common/Import-ControlRegistry.ps1 -Detailed"
pwsh -NoProfile -Command "Get-Help ./Entra/Get-EntraSecurityConfig.ps1 -Detailed"
```

Expected: Help text displays correctly.

- [ ] **Step 4: Test report generation with existing assessment data**

If a previous assessment output folder exists, test report generation:

```bash
pwsh -NoProfile -Command "& ./Common/Export-AssessmentReport.ps1 -AssessmentFolder '<path-to-existing-output>'"
```

Verify:
- Report generates without errors
- CIS compliance overview still shows correctly
- SOC 2 appears in the framework selector
- Framework cross-reference columns still render

- [ ] **Step 5: Commit any fixes**

If smoke testing revealed issues, fix and commit:
```bash
git add -A
git commit -m "fix: address smoke test issues in registry-based report pipeline"
```

---

## Chunk 4: Version Bump + Cleanup

### Task 13: Update version and documentation

**Files:**
- Modify: All files listed in `.claude/rules/versions.md` (10 locations)
- Modify: `README.md`
- Modify: `.claude/rules/versions.md`

- [ ] **Step 1: Bump version from 0.4.0 to 0.5.0**

This is a minor version bump (new feature: multi-framework support). Update all 10
locations per `.claude/rules/versions.md`:

1. `Invoke-M365Assessment.ps1` — `.NOTES` block `Version:` line
2. `Invoke-M365Assessment.ps1` — `$script:AssessmentVersion = '0.5.0'`
3. `Common/Export-AssessmentReport.ps1` — `.NOTES` block `Version:` line
4. `Common/Export-AssessmentReport.ps1` — `$assessmentVersion = '0.5.0'`
5. `Entra/Get-EntraSecurityConfig.ps1` — `.NOTES` block
6. `Exchange-Online/Get-ExoSecurityConfig.ps1` — `.NOTES` block
7. `Security/Get-DefenderSecurityConfig.ps1` — `.NOTES` block
8. `Collaboration/Get-SharePointSecurityConfig.ps1` — `.NOTES` block
9. `Collaboration/Get-TeamsSecurityConfig.ps1` — `.NOTES` block
10. `README.md` — Badge `version-0.5.0-blue`

- [ ] **Step 2: Update versions.md to reflect new version**

Change `Current: **0.4.0**` to `Current: **0.5.0**` in `.claude/rules/versions.md`.

- [ ] **Step 3: Verify version consistency**

```powershell
pwsh -NoProfile -Command "Select-String -Path *.ps1,**/*.ps1,README.md -Pattern 'Version:\s+\d+\.\d+\.\d+|AssessmentVersion\s*=|version-\d+\.\d+\.\d+' | Sort-Object Path"
```

All matches should show `0.5.0`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: bump version to 0.5.0 for multi-framework support"
```

---

### Task 14: Clean up migration artifacts

- [ ] **Step 1: Remove temporary mapping CSV**

```bash
pwsh -NoProfile -Command "Remove-Item controls/check-id-mapping.csv -ErrorAction SilentlyContinue"
```

- [ ] **Step 2: Decide on framework-mappings.csv**

The old `Common/framework-mappings.csv` is now replaced by `controls/registry.json`.
Options:
- Delete it (clean break)
- Keep it as a generated export (add a comment header noting it is deprecated)

Recommended: Keep it for now with a deprecation comment in the first line. It may be
useful for users who consume the CSV directly.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: clean up migration artifacts, deprecate framework-mappings.csv"
```

---

## Phase 2 Tasks (Future — Not Part of This Plan)

These are documented here for reference but should be planned separately:

1. **New SOC 2-specific checks** — Create `Purview/Get-PurviewSecurityConfig.ps1`
   collector with audit retention, alert policies, DLP checks. Add access review,
   Secure Score, stale account, and guest lifecycle checks to Entra collector.

2. **SOC 2 native report view** — Add framework-native grouping to the report layer:
   when SOC 2 is selected, re-group findings by CC criteria instead of CIS sections,
   show criteria-coverage scoring, display non-automatable criteria disclaimer.

3. **Evidence package generation** — Map report output to A-Lign audit request IDs,
   generate evidence artifacts per CC criterion.

4. **Additional framework profiles** — Create `nist-800-53-mod.json`,
   `iso-27001.json`, `cmmc-v2.json` profiles for native views. These are mostly data
   tasks once the registry and report framework are in place.
