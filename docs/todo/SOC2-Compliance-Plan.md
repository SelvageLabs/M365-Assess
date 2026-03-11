# M365-Assess: SOC 2 Compliance Assessment Plan

> **Date**: March 2026
> **Scope**: Add SOC 2 Trust Service Criteria assessment capabilities — control verification, evidence collection, and compliance reporting for M365 tenants
> **Prerequisite**: Familiarity with [M365-Expert-Review.md](./M365-Expert-Review.md) gap analysis and [Phase1-Quick-Wins-Plan.md](./Phase1-Quick-Wins-Plan.md)
> **Target Audience**: SMB IT admins and consultants preparing for SOC 2 Type I/II audits

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [SOC 2 Trust Service Criteria](#2-soc-2-trust-service-criteria)
3. [Architecture Overview](#3-architecture-overview)
4. [M365 Data Sources](#4-m365-data-sources)
5. [Control Verification Layer](#5-control-verification-layer)
6. [Evidence Collection Layer](#6-evidence-collection-layer)
7. [Alerting & Monitoring Strategy](#7-alerting--monitoring-strategy)
8. [Relationship to Existing Work](#8-relationship-to-existing-work)
9. [Implementation Phases](#9-implementation-phases)
10. [Report Output](#10-report-output)
11. [Risk & Mitigations](#11-risk--mitigations)
12. [Next Steps](#12-next-steps)

---

## 1. Executive Summary

### Why SOC 2?

The existing CIS M365 v3.1.0 audit script (`CIS_M365_v310_Audit.ps1`) and M365-Assess framework focus on **configuration benchmarks** — verifying that settings match security best practices. SOC 2 extends this into **monitoring and evidence territory** — proving to auditors that controls are active, violations are detected, and remediation is documented.

| Capability | CIS Benchmark (Current) | SOC 2 Assessment (New) |
|-----------|------------------------|----------------------|
| **Focus** | Configuration correctness | Ongoing control effectiveness |
| **Output** | Pass/fail per setting | Control verification + audit evidence |
| **Audience** | IT admins, security teams | SOC 2 auditors, compliance officers |
| **Frequency** | Point-in-time snapshot | Continuous monitoring evidence |
| **Scope** | M365 settings only | Settings + activity logs + incident response |

### Design Principles

1. **Reusable** — Not an internal-only tool; any organization can run this against their M365 tenant
2. **Read-only** — All operations use `Get-*` cmdlets and audit log queries; never modifies tenant configuration
3. **PowerShell-native** — Integrates with M365 APIs using the same Graph SDK and EXO module patterns as the existing framework
4. **Auditor-ready** — Output is structured to map directly to SOC 2 Trust Service Criteria with control references

---

## 2. SOC 2 Trust Service Criteria

### Trust Principles

SOC 2 is organized around five Trust Service Criteria defined by the AICPA. The tool must assess each principle through the lens of M365 controls:

| Principle | Description | M365 Relevance | MVP Scope |
|-----------|------------|-----------------|-----------|
| **Security** | Control who accesses systems; detect and respond to threats | Conditional Access, MFA, Defender alerts, audit logs | Yes |
| **Availability** | Systems remain operational and accessible | Service health, incident response, backup config | Partial |
| **Processing Integrity** | Data processing is accurate and complete | Mail flow rules, DLP policy effectiveness, data validation | No |
| **Confidentiality** | Sensitive data is protected from unauthorized access | Sharing settings, DLP policies, sensitivity labels, encryption | Yes |
| **Privacy** | Personal data is handled responsibly | Data retention, consent management, access controls on PII | No |

> For most SMBs, **Security** and **Confidentiality** are the primary focus areas and form the MVP scope.

### What Auditors Want to See

For each trust principle, the tool must demonstrate three things:

| Auditor Requirement | Description | Tool Capability |
|--------------------|-------------|-----------------|
| **Data Inventory** | You know where the sensitive data lives | Query site permissions, sensitivity labels, DLP coverage |
| **Control Verification** | Access controls are in place and properly configured | Check CA policies, sharing settings, encryption, DLP rules |
| **Monitoring & Evidence** | You're actively watching for violations and can prove it | Pull audit log events, alert history, remediation records |

---

## 3. Architecture Overview

### Two-Layer Design

The SOC 2 tool operates on two complementary layers, both consuming M365 APIs:

```
┌─────────────────────────────────────────────────────────┐
│                    SOC 2 Assessment                      │
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────────┐  │
│  │  Control Verification │  │   Evidence Collection    │  │
│  │                       │  │                          │  │
│  │  Query M365 settings  │  │  Pull audit log events   │  │
│  │  and configurations   │  │  that prove monitoring   │  │
│  │  to confirm controls  │  │  is active               │  │
│  │  are in place         │  │                          │  │
│  └──────────┬────────────┘  └────────────┬─────────────┘  │
│             │                            │                │
│             ▼                            ▼                │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              SOC 2 Compliance Report                 │  │
│  │  Trust Principle → Controls → Evidence → Status      │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Integration with M365-Assess

SOC 2 becomes another assessment framework alongside CIS, extending the existing modular collector design:

```
Invoke-M365Assessment.ps1
  ├─ ... existing collectors ...
  ├─ SOC2/Get-SOC2SecurityControls.ps1        (NEW — Control Verification)
  ├─ SOC2/Get-SOC2ConfidentialityControls.ps1  (NEW — Control Verification)
  ├─ SOC2/Get-SOC2AuditEvidence.ps1           (NEW — Evidence Collection)
  ├─ Export-AssessmentReport.ps1               (MODIFY — add SOC 2 section)
  └─ Common/soc2-control-mapping.json          (NEW — criteria → controls → queries)
```

---

## 4. M365 Data Sources

### Audit & Activity Logs

| Data Source | Purpose | Graph API / Cmdlet | SOC 2 Principle |
|------------|---------|-------------------|-----------------|
| **Unified Audit Log** | Central activity events across M365 services | `Search-UnifiedAuditLog` (EXO) | Security, Confidentiality |
| **Azure AD Sign-in Logs** | Authentication events, failed logins, risky sign-ins | `GET /auditLogs/signIns` | Security |
| **SharePoint Audit Events** | Sharing changes, permission modifications, file access | UAL filter: `SharePoint` | Confidentiality |
| **Exchange Audit Logs** | Mailbox access, forwarding rules, delegation changes | UAL filter: `Exchange` | Security, Confidentiality |
| **Defender Alerts** | Threat detection and incident data | `GET /security/alerts_v2` | Security |

### Configuration Sources

| Data Source | Purpose | Graph API / Cmdlet | SOC 2 Principle |
|------------|---------|-------------------|-----------------|
| **Conditional Access Policies** | Authentication controls | `GET /identity/conditionalAccess/policies` | Security |
| **SharePoint Site Permissions** | Data access controls | `GET /sites/{id}/permissions` | Confidentiality |
| **DLP Policies** | Data loss prevention rules | `Get-DlpCompliancePolicy` (SCC) | Confidentiality |
| **Sensitivity Labels** | Data classification | `GET /security/informationProtection/sensitivityLabels` | Confidentiality |
| **Retention Policies** | Data lifecycle management | `Get-RetentionCompliancePolicy` (SCC) | Confidentiality |

### Graph Scopes Required

New scopes beyond the existing M365-Assess scope sets:

```powershell
# SOC 2 Security
'AuditLog.Read.All'                     # Sign-in logs (already in Identity scope)
'SecurityEvents.Read.All'               # Defender alerts
'SecurityAlert.Read.All'                # Defender alerts v2

# SOC 2 Confidentiality
'Sites.Read.All'                        # SharePoint site permissions
'InformationProtectionPolicy.Read.All'  # Sensitivity labels
```

---

## 5. Control Verification Layer

### Purpose

Query M365 settings and configurations to confirm controls are in place. Each check maps to a specific SOC 2 Trust Service Criterion (TSC).

### Security Controls

| # | TSC Reference | Control Check | Graph Endpoint / Cmdlet | Pass Criteria |
|---|--------------|---------------|------------------------|---------------|
| S-01 | CC6.1 | MFA enforced for all users | `GET /identity/conditionalAccess/policies` | CA policy with MFA grant for all users, or Security Defaults on |
| S-02 | CC6.1 | Sign-in risk policy configured | `GET /identity/conditionalAccess/policies` | Policy with `signInRiskLevels` in conditions |
| S-03 | CC6.1 | User risk policy configured | `GET /identity/conditionalAccess/policies` | Policy with `userRiskLevels` in conditions |
| S-04 | CC6.2 | Admin accounts use phishing-resistant MFA | `GET /reports/authenticationMethods/userRegistrationDetails` | Admins registered for FIDO2 or Windows Hello |
| S-05 | CC6.3 | Role-based access control active | `GET /directoryRoles` + members | Principle of least privilege; limited Global Admins |
| S-06 | CC7.1 | Unified Audit Log enabled | `Get-AdminAuditLogConfig` | `UnifiedAuditLogIngestionEnabled -eq $true` |
| S-07 | CC7.2 | Defender alerts configured | `GET /security/alerts_v2` | Alert policies exist and are active |
| S-08 | CC7.3 | Incident response — alerts reviewed | `GET /security/alerts_v2?$filter=status ne 'new'` | Evidence of alert triage (resolved/inProgress alerts) |

### Confidentiality Controls

| # | TSC Reference | Control Check | Graph Endpoint / Cmdlet | Pass Criteria |
|---|--------------|---------------|------------------------|---------------|
| C-01 | C1.1 | SharePoint sites not publicly shared | `GET /sites/{id}/permissions` | No anonymous access links |
| C-02 | C1.1 | External sharing restricted | SPO Admin: `Get-SPOTenant` | Sharing level not `ExternalUserAndGuestSharing` |
| C-03 | C1.2 | DLP policies active and enforcing | `Get-DlpCompliancePolicy` | At least one policy in enforce mode (not test) |
| C-04 | C1.2 | Sensitivity labels published | `GET /security/informationProtection/sensitivityLabels` | Labels exist and are published to users |
| C-05 | C1.1 | Encryption in transit | Tenant config | TLS 1.2+ enforced (default in M365) |
| C-06 | C1.2 | Data retention policies configured | `Get-RetentionCompliancePolicy` | At least one retention policy active |
| C-07 | C1.1 | Guest access governance | `GET /policies/authorizationPolicy` | Guest invitation restricted to admins |

### Output CSV Columns

All control verification results follow the existing collector pattern:

```
TrustPrinciple, TSCReference, ControlId, ControlName, CurrentValue, ExpectedValue, Status, Severity, Evidence, Remediation
```

---

## 6. Evidence Collection Layer

### Purpose

Pull audit log events that prove monitoring is active and violations are detected. This is the key differentiator from CIS benchmarking — SOC 2 requires **proof over time**, not just point-in-time configuration checks.

### Evidence Queries

| # | TSC Reference | Evidence Type | Query | Time Window |
|---|--------------|---------------|-------|-------------|
| E-01 | CC7.2 | Failed sign-in attempts | `GET /auditLogs/signIns?$filter=status/errorCode ne 0` | Last 30 days |
| E-02 | CC7.2 | Risky sign-in detections | `GET /identityProtection/riskDetections` | Last 30 days |
| E-03 | CC6.1 | MFA challenge events | UAL: `UserLoggedIn` with MFA claim | Last 30 days |
| E-04 | CC7.3 | Alert response activity | `GET /security/alerts_v2` status changes | Last 30 days |
| E-05 | C1.1 | Sharing events detected | UAL: `SharingSet`, `SharingInvitationCreated` | Last 30 days |
| E-06 | C1.1 | Unauthorized sharing blocked | UAL: `SharingSet` with blocked outcome | Last 30 days |
| E-07 | C1.2 | DLP policy matches | UAL: `DlpRuleMatch` | Last 30 days |
| E-08 | CC6.3 | Privileged role changes | `GET /auditLogs/directoryAudits?$filter=category eq 'RoleManagement'` | Last 30 days |

### Evidence Output

Evidence is collected as a separate CSV per trust principle, providing raw audit trail data:

**File: `<Name>-SOC2-Security-Evidence.csv`**
```
TSCReference, EvidenceType, EventDateTime, Actor, Action, Target, Detail, Outcome
```

**File: `<Name>-SOC2-Confidentiality-Evidence.csv`**
```
TSCReference, EvidenceType, EventDateTime, Actor, Action, Target, Detail, Outcome
```

### Auditor Story Example

For each trust principle, the collected data tells a complete story:

> **SharePoint Confidentiality Control**
> - **Control check** (Layer 1): Site permissions verified — not publicly shared
> - **Evidence** (Layer 2): 3 `SharingSet` events detected in last 30 days; all were internal shares
> - **Story for auditor**: "We know where the financial data lives, it's locked down, and we caught 3 sharing events in the last 30 days — all were authorized internal shares."

---

## 7. Alerting & Monitoring Strategy

### MVP: Scheduled Script

For the initial release, the evidence collection script can be run on a schedule:

| Deployment Model | Technology | Frequency | Notes |
|-----------------|-----------|-----------|-------|
| **Workstation** | Windows Task Scheduler | Daily/Weekly | Simplest setup; consultant runs on demand |
| **Azure** | Azure Automation Runbook | Daily | Uses Managed Identity; stores output in Blob |
| **Azure** | Azure Function App (timer trigger) | Hourly/Daily | Same PowerShell logic; scales to multi-tenant |

### Suspicious Activity Definitions

The tool defines what "suspicious" means per trust principle, with configurable thresholds:

```powershell
# Default thresholds (overridable via parameter or config file)
$SOC2Thresholds = @{
    FailedSignInsPerUser    = 10    # Per user, per day
    ExternalSharingEvents   = 5     # Total, per day
    PrivilegedRoleChanges   = 3     # Total, per day
    DLPPolicyMatches        = 10    # Total, per day
    UnresolvedAlerts        = 5     # Active at any time
    RiskyUserCount          = 0     # Any risky user is flagged
}
```

### Scale Path

```
MVP (Local Script)
  └─ Azure Automation Runbook (scheduled, single tenant)
       └─ Azure Function App (multi-tenant, API-driven)
            └─ Future: UI dashboard (if commercial viability proven)
```

---

## 8. Relationship to Existing Work

### Overlap with Current Collectors

Several existing M365-Assess collectors already produce data relevant to SOC 2. The SOC 2 module should **consume existing collector output** rather than duplicate API calls:

| Existing Collector | SOC 2 Relevance | Reuse Strategy |
|-------------------|-----------------|----------------|
| `Get-EntraSecurityConfig.ps1` | CC6.1 — MFA, CA policies | Reference CIS results for control verification |
| `Get-AdminRoleReport.ps1` | CC6.3 — RBAC, least privilege | Import CSV for privileged account analysis |
| `Get-MfaReport.ps1` | CC6.1 — MFA adoption evidence | Import CSV for MFA coverage metrics |
| `Get-DlpPolicyReport.ps1` | C1.2 — DLP controls | Import CSV for policy inventory |
| `Get-SecureScoreReport.ps1` | Multiple — overall posture | Reference score as SOC 2 context |
| `Get-DefenderPolicyReport.ps1` | CC7.1 — threat detection | Import CSV for Defender coverage |
| `Get-ExoSecurityConfig.ps1` | CC7.1 — UAL enabled | Reference CIS results for audit log status |

### New vs. Reused

| Component | Status |
|-----------|--------|
| Control verification checks | **New** — SOC 2-specific logic mapping TSC references |
| Evidence collection queries | **New** — audit log queries with SOC 2 evidence framing |
| SOC 2 control mapping file | **New** — `soc2-control-mapping.json` |
| HTML report SOC 2 section | **New** — added to existing report generator |
| Collector execution pattern | **Reused** — follows existing `[CmdletBinding()]` + CSV output pattern |
| Graph connection & auth | **Reused** — uses existing `Connect-Service` infrastructure |
| Orchestrator wiring | **Modified** — new section added to `$collectorMap` |

---

## 9. Implementation Phases

### Phase 1: Research & Mapping

**Goal**: Map SOC 2 Trust Service Criteria to specific M365 audit events and configurations

| # | Task | Deliverable | Effort |
|---|------|-------------|--------|
| 1 | Deep-dive on AICPA SOC 2 Trust Service Criteria | Annotated criteria document | Medium |
| 2 | Map each criterion to M365 controls and audit queries | `soc2-control-mapping.json` | Medium |
| 3 | Define MVP scope (Security + Confidentiality only) | Scoped control list | Low |
| 4 | Identify required Graph scopes and EXO cmdlets | Scope manifest | Low |

### Phase 2: Control Verification MVP

**Goal**: Build PowerShell collectors for SOC 2 control checks (Security + Confidentiality)

| # | Task | Deliverable | Effort |
|---|------|-------------|--------|
| 1 | Create `SOC2/` directory | New directory in project root | Trivial |
| 2 | Build `Get-SOC2SecurityControls.ps1` | 8 security control checks (S-01 through S-08) | Medium |
| 3 | Build `Get-SOC2ConfidentialityControls.ps1` | 7 confidentiality control checks (C-01 through C-07) | Medium |
| 4 | Create `Common/soc2-control-mapping.json` | Structured mapping of TSC → M365 controls → queries | Medium |
| 5 | Wire collectors into orchestrator | New SOC 2 section in `$collectorMap` and `$sectionScopeMap` | Low |
| 6 | Lint and parse-check all new files | PSScriptAnalyzer clean | Low |

### Phase 3: Evidence Collection

**Goal**: Add audit log evidence queries to prove monitoring is active

| # | Task | Deliverable | Effort |
|---|------|-------------|--------|
| 1 | Build `Get-SOC2AuditEvidence.ps1` | 8 evidence queries (E-01 through E-08) | Medium |
| 2 | Implement configurable thresholds | `$SOC2Thresholds` hashtable with overrides | Low |
| 3 | Add evidence CSV output (two files) | Security evidence + Confidentiality evidence CSVs | Low |
| 4 | Wire evidence collector into orchestrator | `HasSecondary` pattern for dual CSV output | Low |

### Phase 4: Reporting & Polish

**Goal**: Integrate SOC 2 findings into the HTML report and add gap analysis

| # | Task | Deliverable | Effort |
|---|------|-------------|--------|
| 1 | Add SOC 2 section to HTML report | Trust principle dashboard with control status | Medium |
| 2 | Add remediation guidance per control | Actionable fix instructions in report | Medium |
| 3 | Build gap analysis summary | "Controls met vs. gaps" per trust principle | Low |
| 4 | Add SOC 2 to framework mappings CSV | Cross-reference CIS controls with SOC 2 TSC | Low |

### Phase 5: Alerting & Automation (Future)

**Goal**: Enable scheduled monitoring with alert notifications

| # | Task | Deliverable | Effort |
|---|------|-------------|--------|
| 1 | Build scheduled evidence collection script | Task Scheduler / Azure Automation compatible | Medium |
| 2 | Add email/Teams notification for threshold breaches | Alert delivery mechanism | Medium |
| 3 | Azure Function App packaging | Timer-triggered function with same PowerShell logic | High |
| 4 | Multi-tenant support | Tenant roster with per-tenant credentials | High |

---

## 10. Report Output

### SOC 2 Section in HTML Report

The SOC 2 assessment results integrate into the existing HTML report as a new top-level section:

```
Assessment Report
  ├─ Executive Summary (existing)
  ├─ Identity & Access (existing)
  ├─ Email Security (existing)
  ├─ ...
  ├─ SOC 2 Compliance (NEW)
  │   ├─ Trust Principle: Security
  │   │   ├─ Control Status Table (pass/fail per TSC)
  │   │   └─ Evidence Summary (event counts, last 30 days)
  │   ├─ Trust Principle: Confidentiality
  │   │   ├─ Control Status Table
  │   │   └─ Evidence Summary
  │   └─ Gap Analysis
  │       ├─ Controls Met vs. Gaps (donut chart)
  │       └─ Prioritized Remediation Table
  └─ Appendix (existing)
```

### CSV Output Files

| File | Content | Rows |
|------|---------|------|
| `<Name>-SOC2-Security-Controls.csv` | Security control verification results | 8 (one per control) |
| `<Name>-SOC2-Confidentiality-Controls.csv` | Confidentiality control verification results | 7 (one per control) |
| `<Name>-SOC2-Security-Evidence.csv` | Security audit log evidence | Variable (event count) |
| `<Name>-SOC2-Confidentiality-Evidence.csv` | Confidentiality audit log evidence | Variable (event count) |

### Control Mapping File

`Common/soc2-control-mapping.json` provides the structured reference linking trust principles to M365 controls:

```json
{
  "version": "1.0",
  "framework": "SOC 2 Type II",
  "trustPrinciples": {
    "Security": {
      "criteria": [
        {
          "id": "CC6.1",
          "name": "Logical and Physical Access Controls",
          "controls": [
            {
              "controlId": "S-01",
              "name": "MFA Enforced for All Users",
              "graphEndpoint": "/identity/conditionalAccess/policies",
              "passCriteria": "CA policy with MFA grant for all users or Security Defaults enabled",
              "evidenceQuery": "UAL: UserLoggedIn with MFA claim"
            }
          ]
        }
      ]
    }
  }
}
```

---

## 11. Risk & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **SOC 2 criteria interpretation** | Incorrect mapping of TSC to M365 controls | Validate mappings against official AICPA guidance; flag as "community interpretation" in docs |
| **Unified Audit Log retention** | Default 180-day retention may miss older evidence | Document retention requirements; recommend E5 or audit log add-on for 1-year retention |
| **License-gated features** | Some evidence sources require E5/P2 (e.g., risk detections, sensitivity labels) | Detect licensing and skip gracefully, following the existing license detection pattern |
| **Large audit log volumes** | Tenants with high activity may return massive result sets | Implement paging, date windowing, and `$top` limits on all audit queries |
| **Not a substitute for SOC 2 audit** | Users may mistake tool output for actual SOC 2 certification | Add prominent disclaimer: "This tool assists with SOC 2 readiness assessment. It does not constitute a SOC 2 audit or certification." |
| **Scope creep beyond Security + Confidentiality** | Attempting all 5 trust principles in MVP delays delivery | MVP explicitly scopes to Security + Confidentiality; remaining principles deferred to Phase 5+ |
| **Overlap with CIS collectors** | Duplicating API calls already made by existing collectors | SOC 2 collectors import existing CSV outputs where possible, only making new API calls for SOC 2-specific evidence |

---

## 12. Next Steps

Ordered by dependency:

| # | Task | Phase | Dependency |
|---|------|-------|------------|
| 1 | Deep-dive research on SOC 2 Trust Service Criteria (official AICPA docs) | Phase 1 | None |
| 2 | Map each criterion to M365 audit events and queryable configurations | Phase 1 | Task 1 |
| 3 | Define MVP scope (Security + Confidentiality principles only) | Phase 1 | Task 2 |
| 4 | Create `SOC2/` directory and `soc2-control-mapping.json` | Phase 2 | Task 3 |
| 5 | Build proof-of-concept `Get-SOC2SecurityControls.ps1` | Phase 2 | Task 4 |
| 6 | Build `Get-SOC2ConfidentialityControls.ps1` | Phase 2 | Task 4 |
| 7 | Build `Get-SOC2AuditEvidence.ps1` | Phase 3 | Tasks 5-6 |
| 8 | Wire SOC 2 collectors into orchestrator | Phase 2-3 | Tasks 5-7 |
| 9 | Design HTML report SOC 2 section | Phase 4 | Task 8 |
| 10 | Add SOC 2 to framework mappings CSV | Phase 4 | Task 2 |
