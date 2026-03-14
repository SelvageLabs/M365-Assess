# v0.8.2 CI & Quality Sprint Design

## Overview

Four issues delivering CI infrastructure, test coverage, a bug fix, and dependency management. Execution order reflects dependencies: CI pipeline first, then tests that run in it, then independent fixes.

## Issue #55: GitHub Actions CI

### Architecture

Single workflow file `.github/workflows/ci.yml` with 3 parallel jobs running on `windows-latest`:

```
ci.yml
├── lint (PSScriptAnalyzer)
├── test (Pester 5.x)
└── version-check (consistency across 30 locations)
```

**Triggers:** `pull_request` to `main`, `push` to `main`.

### Lint Job

1. Checkout repo
2. Install PSScriptAnalyzer module
3. Run `Invoke-ScriptAnalyzer` against all `.ps1` files using a shared settings file
4. Fail on Error/Warning severity; allow Information

**Settings file:** `PSScriptAnalyzerSettings.psd1` at repo root. Rules to include:
- `PSAvoidUsingCmdletAliases`
- `PSAvoidUsingPositionalParameters`
- `PSAvoidGlobalVars` (exclude known `$global:` usage in `Update-CheckProgress`)
- `PSUseDeclaredVarsMoreThanAssignments`
- `PSAvoidUsingWriteHost` (exclude -- assessment uses Write-Host intentionally)
- `PSUseShouldProcessForStateChangingFunctions` (exclude -- read-only tool)

Excluded rules documented with rationale in the settings file.

### Test Job

1. Checkout repo
2. Install Pester module (5.x)
3. Run `Invoke-Pester -Path ./tests/ -CI` (CI switch enables NUnit output + non-zero exit on failure)
4. Upload test results as artifact

### Version Check Job

1. Checkout repo
2. Run `Select-String` across all 30 version locations from `.claude/rules/versions.md`
3. Extract version strings, compare for consistency
4. Fail if any file has a mismatched version

### Files Created

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yml` | Workflow definition |
| `PSScriptAnalyzerSettings.psd1` | Shared analyzer rules |

---

## Issue #57: Pester Coverage Expansion

### Strategy

Two tiers of tests, both runnable without M365 credentials:

**Tier 1: Smoke tests** (all scripts)
- Parse validation: `[scriptblock]::Create((Get-Content $file -Raw))` for every `.ps1`
- Parameter validation: dot-source + `Get-Command` confirms exported functions exist
- Help validation: `Get-Help` returns non-empty synopsis for scripts with comment-based help

**Tier 2: Mock-based collector test** (one collector as template)
- Target: `Entra/Get-EntraSecurityConfig.ps1` (largest collector, most patterns)
- Mock `Invoke-MgGraphRequest` to return canned JSON responses
- Verify: correct number of settings returned, CheckId format, Status values are valid enums
- Verify: `Add-Setting` produces `[PSCustomObject]` with required properties (CheckId, Name, Status, Value, Expected, Section)

### Test File Structure

```
tests/
├── Common/
│   └── Import-ControlRegistry.Tests.ps1  (existing)
├── controls/
│   └── registry-integrity.Tests.ps1      (existing)
├── Smoke/
│   └── Script-Validation.Tests.ps1       (new -- Tier 1)
└── Entra/
    └── Get-EntraSecurityConfig.Tests.ps1  (new -- Tier 2)
```

### Mock Pattern for Collectors

```powershell
BeforeAll {
    # Stub Update-CheckProgress so Add-Setting's guard passes
    function global:Update-CheckProgress { }

    # Dot-source the collector
    . "$PSScriptRoot/../../Entra/Get-EntraSecurityConfig.ps1"
}

Describe 'Get-EntraSecurityConfig' {
    BeforeAll {
        Mock Invoke-MgGraphRequest -MockWith { <canned response> }
    }

    It 'Returns settings with valid CheckId format' {
        $results = Get-EntraSecurityConfig
        $results | ForEach-Object {
            $_.CheckId | Should -Match '^[A-Z]+(-[A-Z0-9]+)+-\d{3}$'
        }
    }
}
```

### Files Created

| File | Purpose |
|------|---------|
| `tests/Smoke/Script-Validation.Tests.ps1` | Tier 1 smoke tests |
| `tests/Entra/Get-EntraSecurityConfig.Tests.ps1` | Tier 2 mock collector test |

---

## Issue #72: Breakglass Exclusion from Admin Count

### Current Behavior

`ENTRA-ADMIN-001` counts all Global Administrator role members. `ENTRA-ADMIN-003` separately detects breakglass accounts by name pattern. The two checks don't communicate.

### Design

Extract breakglass detection into a shared helper function at the top of `Get-EntraSecurityConfig.ps1`:

```powershell
function Get-BreakGlassAccounts {
    param([array]$Users)
    $patterns = @('break.?glass', 'emergency.?access', 'breakglass', 'emer.?admin')
    $regex = ($patterns | ForEach-Object { "($_)" }) -join '|'
    $Users | Where-Object {
        $_.displayName -match $regex -or $_.userPrincipalName -match $regex
    }
}
```

**ENTRA-ADMIN-001 change:** After fetching role members, call `Get-BreakGlassAccounts` to identify breakglass members. Subtract from the count. Add a detail note like "X Global Admins (excluding Y breakglass accounts)".

**ENTRA-ADMIN-003 change:** Replace inline pattern matching with a call to `Get-BreakGlassAccounts`. Same behavior, shared logic.

### Edge Cases

- Zero breakglass accounts found: count is unchanged (no subtraction)
- All admins match breakglass pattern: count goes to 0, status = Fail (< 2 non-breakglass admins)
- Breakglass account not in Global Admin role: no effect on ENTRA-ADMIN-001 (filter is role members only)

### Files Modified

| File | Change |
|------|--------|
| `Entra/Get-EntraSecurityConfig.ps1` | Add `Get-BreakGlassAccounts`, update ENTRA-ADMIN-001 and ENTRA-ADMIN-003 |

---

## Issue #60: Dependency Pinning

### Current State

Only `Microsoft.Graph.Authentication >= 2.0.0` is in `RequiredModules`. EXO 3.7.1 is hardcoded as a string in the orchestrator. All other Graph submodules are undeclared.

### Design

**1. Expand `M365-Assess.psd1` RequiredModules:**

Add all modules actually imported across the codebase with minimum versions matching the known-good combination:

```powershell
RequiredModules = @(
    @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }
    @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.7.0'; MaximumVersion = '3.7.99' }
    # Graph submodules as needed
)
```

Note: EXO uses `MaximumVersion` to cap below 3.8.0 (known incompatible).

**2. Create `docs/COMPATIBILITY.md`:**

Human-readable matrix documenting:
- Known-good module versions (tested combinations)
- PowerShell version requirements (7.0+)
- Known incompatibilities (EXO >= 3.8.0)
- Module installation commands

**3. CI version-check job enhancement:**

Add a step that compares `RequiredModules` entries against actual `Import-Module` / `Invoke-MgGraphRequest` usage to catch undeclared dependencies.

### Files Modified/Created

| File | Change |
|------|--------|
| `M365-Assess.psd1` | Expand `RequiredModules` with all dependencies |
| `Invoke-M365Assessment.ps1` | Reference manifest versions instead of hardcoded strings |
| `docs/COMPATIBILITY.md` | New -- human-readable compatibility matrix |

---

## Sprint Summary

| Issue | Files Created | Files Modified | Effort |
|-------|--------------|----------------|--------|
| #55 CI | 2 | 0 | Medium |
| #57 Pester | 2 | 0 | Medium |
| #72 Breakglass | 0 | 1 | Small |
| #60 Deps | 1 | 2 | Small |
| **Total** | **5 new** | **3 modified** | -- |
