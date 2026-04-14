# M365-Assess — Project Intelligence

## What This Is
PowerShell security assessment tool for Microsoft 365 tenants. Published to PSGallery
as a proper module (`M365-Assess`). Produces HTML, XLSX, and JSON output mapped to
15 compliance frameworks (CIS, NIST, CMMC, SCF, etc.).

## Architecture

### Module Structure
```
src/M365-Assess/
├── M365-Assess.psd1            # Module manifest — version source of truth
├── M365-Assess.psm1            # Root module
├── Invoke-M365Assessment.ps1   # Main orchestrator (~970 lines)
├── Orchestrator/               # 9 support modules (Connect-RequiredService,
│                               #   Test-GraphPermissions, Show-InteractiveWizard, etc.)
├── Common/                     # Report, registry, framework, export helpers
│   ├── SecurityConfigHelper.ps1     # Collector contract (Initialize/Add-Setting/Export)
│   ├── Import-ControlRegistry.ps1   # Loads registry.json + licensing-overlay.json
│   ├── Export-AssessmentReport.ps1  # HTML report orchestrator
│   └── Export-ComplianceMatrix.ps1  # XLSX export
├── Entra/                      # CA, MFA, identity checks
├── Security/                   # Defender, MDI checks
├── Exchange-Online/            # EXO, DNS checks
├── SharePoint/                 # SPO, Teams checks
├── Purview/                    # Compliance checks
└── controls/
    ├── registry.json            # 253 checks (222 CheckID upstream + 31 local extensions)
    ├── licensing-overlay.json   # Maps CheckID E3/E5 minimum → exact service plan IDs
    ├── risk-severity.json       # Risk scores per checkId
    └── frameworks/              # 15 framework JSON files (auto-discovered)
```

### Collector Contract
Every collector dot-sources `SecurityConfigHelper.ps1` and calls:
1. `Initialize-SecurityConfig` — creates a fresh `$ctx.Settings` (List) + `$ctx.CheckIdCounter`
2. `Add-Setting @{ CheckId; Category; Setting; CurrentValue; RecommendedValue; Status; Remediation }` — records one check result; CheckId is auto-sub-numbered (e.g., `CA-REPORTONLY-001.1`)
3. `Export-SecurityConfigReport` — returns structured results

Status values: `Pass` | `Fail` | `Warning` | `Review` | `Info` | `Skipped`

### CheckID Integration
`registry.json` is synced from CheckID pinned releases (CI: `sync-checkid` cron, weekly).
**Never load from CheckID main branch** — always use a tagged release.

Local extension checks (31 total) are M365-Assess-specific checks not yet in CheckID
upstream. **The sync script must preserve them by checkId prefix or explicit list.**
When adding new local extension checks, register them in the sync preservation list.

### DNS Collector
DNS checks run **after all other sections** — domains are prefetched from Graph at
connect time and passed via `-AcceptedDomains`. `.onmicrosoft.com` domains are filtered
at source (they cannot have public DNS records by design).

## Key Workflows

### Running Tests (CI gate: 65% coverage)
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path './tests' -Output Detailed"
# Single domain:
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Entra' -Output Detailed"
```

### Pester test pattern for collector tests
Tests filter by `$_.Setting` (human-readable name), NOT by `$_.CheckId` — the stored
CheckId is sub-numbered (e.g., `CA-REPORTONLY-001.1`). See `.claude/rules/pester.md`.

### Adding a New Check
1. Add `Add-Setting` call in the relevant collector
2. Add entry to `controls/registry.json` (v2.0.0 schema — copy adjacent CA-* entry)
3. Add licensing entry to `licensing-overlay.json` if E5-gated
4. Write Pester tests
5. Run PSScriptAnalyzer lint before committing

### Linting
```powershell
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path '.' -Recurse -Severity Warning -ExcludePath '.claude'"
```

## Critical Rules
| Rule | Why |
|------|-----|
| **NEVER bump version without user approval** | See `.claude/rules/releases.md` |
| **NEVER `Import-Module` before running assessment** | Causes stale code from module cache |
| **NEVER commit tenant names/domains/UPNs** | Public repo — no PII in issues/PRs/commits |
| **NEVER force-push main** | Protected branch; PRs required |
| **Version lives in 4 locations** | See `.claude/rules/versions.md` |
| **Preserve local extensions on registry sync** | Sync overwrites — list them explicitly |

## Key File Paths
| File | Purpose |
|------|---------|
| `src/M365-Assess/M365-Assess.psd1` | Version (ModuleVersion field) |
| `src/M365-Assess/Invoke-M365Assessment.ps1` | Main entry point |
| `src/M365-Assess/Common/SecurityConfigHelper.ps1` | Collector contract functions |
| `src/M365-Assess/controls/registry.json` | Check registry (253 entries, v2.0.0 schema) |
| `src/M365-Assess/controls/licensing-overlay.json` | E3/E5 → service plan ID mapping |
| `CHANGELOG.md` | Release notes (Keep a Changelog format) |

## Shell / Execution Rules
- Always use `pwsh` (PowerShell 7.x) — never `powershell.exe`
- Bash tool runs through Git Bash: `$` variables are mangled inline. Write temp `.ps1` files
  for anything with `$` vars; run with `pwsh -NoProfile -File ./_tmp.ps1`; then delete.
- See `.claude/rules/` for coding standards (path-scoped, auto-loaded):
  - `powershell.md` — PS conventions (*.ps1, *.psm1, *.psd1)
  - `pester.md` — Test conventions (*.Tests.ps1)
  - `releases.md` — Version bump and release workflow
  - `versions.md` — All 4 version file locations
