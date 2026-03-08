# Add multi-framework compliance mapping (NIST, ISO, STIG, PCI, CMMC)

## Overview

Add cross-framework compliance mapping so each security config finding shows which controls it satisfies across multiple frameworks — not just CIS. Most organizations have one primary framework and need to demonstrate coverage against others. Showing the matrix eliminates duplicate work for consultants.

## Research Findings

### Frameworks to Implement (Priority Order)

| Framework | Public Catalog? | M365 Relevance | Notes |
|-----------|----------------|----------------|-------|
| **CIS M365 v6.0.1** | Yes (free with account) | Direct technical controls | **Already implemented** (~140 controls) |
| **NIST 800-53 Rev 5** | Yes (fully public) | Strong — AC, AU, IA, SC families map directly | 20 control families; NIST publishes official crosswalks to CIS and ISO |
| **NIST CSF 2.0** | Yes (fully public) | Good — higher-level categories map to 800-53 | 6 functions, 22 categories. NIST OLIR program provides official mappings |
| **DISA STIGs** | Yes (public.cyber.mil) | Direct — Entra ID STIG, O365 ProPlus STIG v3r4, Intune Desktop STIG | Checklists downloadable without CAC from NIST NCP |
| **ISO 27001:2022** | Control *titles* are public; full standard is paid | Good — Annex A maps well to technical controls | CIS publishes official CIS→ISO mapping; NIST publishes 800-53→ISO crosswalk |
| **PCI DSS v4.0** | Yes (PCI SSC website) | Moderate — Req 1-2 (access), 5 (malware), 8 (auth), 10 (logging), 12 (policy) | Focused on cardholder data environments |
| **CMMC 2.0** | Yes (maps to NIST 800-171) | Good — identity, access, audit, config mgmt | 3 levels; Level 2 = NIST 800-171 Rev 2 (110 practices) |
| **SOX** | Via COBIT/COSO frameworks | Low-moderate — access controls, audit logging, change mgmt | More process/governance than technical; map via COBIT 2019 |
| **HIPAA Security Rule** | Yes (HHS.gov) | Moderate — access controls, audit, integrity, transmission security | 18 standards, 36 implementation specifications |
| **FedRAMP** | Yes (based on NIST 800-53) | Direct — same controls as 800-53 with baselines (Low/Moderate/High) | Primarily relevant for GCC/GCCHigh tenants |

### What Competitors Do

| Tool | Frameworks | Multi-Framework Approach |
|------|-----------|------------------------|
| **Maester** | CIS Benchmarks, CISA SCuBA, MITRE ATT&CK (via EIDSCA) | Per-test tags with framework prefix (MS.*, EIDSCA.*) |
| **Prowler** | 39 frameworks (CIS, NIST 800-53, NIST CSF, ISO 27001, PCI-DSS, HIPAA, SOC2, FedRAMP, GDPR, MITRE ATT&CK, etc.) | Each check tagged with multiple framework IDs; compliance dashboard per framework |
| **CISA ScubaGear** | CISA SCuBA baselines only | Single-framework, no cross-mapping |
| **Monkey365** | CIS Azure/M365 (160+ checks), plans for NIST/HIPAA/PCI | JSON rule files with compliance tags |
| **Microsoft Compliance Manager** | 360+ regulatory templates (NIST, ISO, CMMC, FedRAMP, HIPAA, PCI, GDPR, AI regs) | Per-assessment template approach; improvement actions shared across assessments |
| **Microsoft Secure Score** | Implicitly maps to NIST CSF, CIS, ISO 27001, NIS2 | Single score with recommendations; no explicit multi-framework view |

### Key Cross-Reference Resources (Free & Public)

1. **Secure Controls Framework (SCF)** — Open-source metaframework with 1,300+ controls mapped to 100+ frameworks. Free download from [securecontrolsframework.com](https://securecontrolsframework.com/) and [GitHub](https://github.com/securecontrolsframework/securecontrolsframework). Uses NIST IR 8477 Set Theory mapping methodology.
2. **CIS Official Mappings** — CIS Controls v8.1 → NIST 800-53 Rev 5, NIST CSF 2.0, NIST 800-171, ISO 27001:2022. Available from [cisecurity.org](https://www.cisecurity.org/cybersecurity-tools/mapping-compliance/mapping-and-compliance-with-the-cis-controls)
3. **NIST OLIR Program** — Official crosswalks between 800-53, CSF, ISO, and others at [csrc.nist.gov/projects/olir](https://csrc.nist.gov/projects/olir/informative-reference-catalog)
4. **DISA STIG Downloads** — Entra ID, O365 ProPlus, Intune Desktop STIGs at [public.cyber.mil/stigs](https://public.cyber.mil/stigs/) and [ncp.nist.gov](https://ncp.nist.gov/)

---

## Current Implementation

Each security config script (`Get-EntraSecurityConfig.ps1`, `Get-ExoSecurityConfig.ps1`, etc.) produces findings with this CSV schema:

```
Category | Setting | CurrentValue | RecommendedValue | Status | CisControl | Remediation
```

The `CisControl` column holds CIS benchmark IDs (e.g., `1.1.3`, `5.1.5.1`). The HTML report aggregates findings with non-empty `CisControl` into a CIS Compliance Summary section with score cards and a sorted findings table.

---

## Proposed Architecture

### Option A: Mapping Table (Recommended)

Create a CSV/JSON mapping file (`Common/framework-mappings.csv`) that maps each CIS control to other framework controls:

```csv
CisControl,NistCsf,Nist80053,Iso27001,Stig,PciDss,Cmmc,Hipaa
1.1.3,PR.AC-6,AC-6(5),A.8.2,V-260333,8.6.1,AC.L2-3.1.6,§164.312(a)(1)
5.1.5.1,PR.AC-1,AC-3,A.8.3,,8.3.1,AC.L2-3.1.1,§164.312(a)(1)
6.5.1,PR.AC-7,IA-2,A.8.5,V-260337,8.3.1,IA.L2-3.5.3,§164.312(d)
```

**Advantages:**
- No changes to collector scripts — they keep producing `CisControl` as-is
- Single file to maintain framework mappings
- Export-AssessmentReport.ps1 joins findings → mappings at report generation time
- Easy to add frameworks later (just add a column)
- Community can contribute mappings without touching PowerShell code
- Mapping file can be sourced from SCF or CIS official crosswalks

### Option B: Multiple Columns in Collectors

Add `NistControl`, `IsoControl`, `StigId`, etc. columns directly to each `Add-Setting` call in every security config script.

**Disadvantages:**
- Touches every collector script
- Duplicates mapping data across 5+ files
- Harder to maintain and update

### Recommendation: Option A with a matrix view in the HTML report

---

## HTML Report Changes

1. **Framework Selector** — Add tabs or toggle at the top of the compliance section: CIS | NIST CSF | NIST 800-53 | ISO 27001 | STIG | PCI DSS | CMMC
2. **Cross-Reference Matrix** — For each finding, show which frameworks it maps to (with control IDs). This is the "show the matrix" view.
3. **Per-Framework Score Cards** — Same compliance percentage calculation but filtered per framework
4. **Export** — CSV export includes all framework columns for external GRC tools

### Data Flow

```
Collector → CSV (with CisControl) → Export-AssessmentReport.ps1
                                          ↓
                                    Reads framework-mappings.csv
                                          ↓
                                    Joins on CisControl
                                          ↓
                                    Renders multi-framework matrix
```

---

## Implementation Plan

### Phase 1: Mapping Foundation
- [ ] Create `Common/framework-mappings.csv` with CIS → NIST CSF, NIST 800-53, ISO 27001 mappings
- [ ] Source initial mappings from CIS official crosswalks and SCF
- [ ] Cover all ~140 existing CIS controls

### Phase 2: DISA STIG Integration
- [ ] Download Entra ID STIG and O365 ProPlus STIG checklists
- [ ] Map STIG IDs to existing CIS controls in framework-mappings.csv
- [ ] Add any STIG checks that don't have a CIS equivalent as new security config findings

### Phase 3: HTML Report Enhancement
- [ ] Update Export-AssessmentReport.ps1 to read framework-mappings.csv
- [ ] Add framework selector tabs to compliance section
- [ ] Add cross-reference matrix table showing all framework mappings per finding
- [ ] Add per-framework score cards
- [ ] Keep CIS as the default/primary view

### Phase 4: Additional Frameworks
- [ ] Add PCI DSS v4.0 column (focus on Req 1, 2, 5, 8, 10, 12)
- [ ] Add CMMC 2.0 column (maps through NIST 800-171)
- [ ] Add HIPAA Security Rule column
- [ ] Add SOX/COBIT column (where applicable)

### Phase 5: Documentation
- [ ] Update README.md with framework coverage
- [ ] Document how to add custom framework mappings
- [ ] Add mapping methodology notes (source attribution for crosswalks)

---

## References

- [Secure Controls Framework (SCF)](https://securecontrolsframework.com/) — Open-source metaframework, 100+ framework mappings
- [CIS Controls Mapping](https://www.cisecurity.org/cybersecurity-tools/mapping-compliance/mapping-and-compliance-with-the-cis-controls) — Official CIS crosswalks
- [NIST OLIR Catalog](https://csrc.nist.gov/projects/olir/informative-reference-catalog) — Official NIST framework crosswalks
- [DISA STIG Downloads](https://public.cyber.mil/stigs/) — Public STIG checklists
- [Microsoft Compliance Manager Templates](https://learn.microsoft.com/en-us/purview/compliance-manager-regulations-list) — 360+ regulatory templates
- [Prowler Compliance Frameworks](https://github.com/prowler-cloud/prowler) — 39 frameworks across AWS/Azure/M365
- [Maester](https://maester.dev/) — CIS, CISA SCuBA, MITRE ATT&CK for M365
