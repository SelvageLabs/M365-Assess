# SOC 2 Daily Audit Log Monitoring & Automation Strategy

> **Date**: March 2026
> **Scope**: Comprehensive audit log event inventory, daily automated evidence collection, and Azure/Power Platform execution strategy
> **Prerequisite**: [SOC2-Compliance-Plan.md](./SOC2-Compliance-Plan.md) (Phase 1 controls already implemented)
> **Target Audience**: SMB IT admins, compliance officers, and consultants operating SOC 2 Type II programs

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Audit Log Event Inventory](#2-audit-log-event-inventory)
3. [API Endpoints & Permissions Reference](#3-api-endpoints--permissions-reference)
4. [Graph API vs Unified Audit Log](#4-graph-api-vs-unified-audit-log)
5. [Data Retention Limits](#5-data-retention-limits)
6. [Daily Monitoring Requirements by TSC](#6-daily-monitoring-requirements-by-tsc)
7. [Auditor Evidence Expectations](#7-auditor-evidence-expectations)
8. [Alerting Thresholds](#8-alerting-thresholds)
9. [Automation Platform Comparison](#9-automation-platform-comparison)
10. [Recommended Architecture](#10-recommended-architecture)
11. [Power Platform Dashboard Option](#11-power-platform-dashboard-option)
12. [Gap Analysis vs Current Implementation](#12-gap-analysis-vs-current-implementation)
13. [Implementation Phases](#13-implementation-phases)

---

## 1. Executive Summary

The existing M365-Assess SOC 2 module provides **point-in-time configuration checks** (15 controls across Security and Confidentiality) and **30-day evidence snapshots** (6 evidence queries). This is sufficient for initial readiness assessment but insufficient for SOC 2 Type II, which requires **continuous monitoring with provable daily cadence** over the 3–12 month observation window.

This strategy extends the tooling to:
- Check **every relevant M365 audit log event category** (not just the 6 currently queried)
- Run checks **daily on a schedule** via Azure Automation
- Store evidence in **Log Analytics** with 365+ day retention
- Alert on **threshold breaches** in near-real-time
- Provide a **compliance officer dashboard** with daily sign-off workflow

---

## 2. Audit Log Event Inventory

### 2.1 Entra ID Audit Logs

#### Directory Audits — SOC 2 Relevance: CC6.1, CC6.2, CC6.3, CC7.1

| Operation Category | Key Operations | TSC Mapping |
|---|---|---|
| RoleManagement | Add/Remove member to role, Add eligible member (PIM) | CC6.3 |
| UserManagement | Add/Delete/Disable user, Reset password | CC6.1, CC6.2 |
| GroupManagement | Add/Remove member, Add/Delete group | CC6.1, CC6.3 |
| ApplicationManagement | Add app, Update credentials, Add service principal | CC6.1 |
| Policy | Add/Update/Delete Conditional Access policy | CC6.1, CC5.x |
| DeviceManagement | Register/Delete/Enable/Disable device | CC6.1 |
| ExternalIdentities | Invite external user, Redeem invite | CC6.6, C1.1 |
| PIM | Activate/Deactivate eligible role assignment | CC6.3 |

#### Sign-in Logs (4 types) — SOC 2 Relevance: CC6.1, CC7.2

| Type | Description | SOC 2 Use |
|---|---|---|
| interactiveUser | User-initiated (password, MFA prompts) | Failed sign-ins, MFA enforcement evidence |
| nonInteractiveUser | Token refresh, SSO, background auth | Compromised token reuse detection |
| servicePrincipal | App/service principal auth | App-to-app access monitoring |
| managedIdentity | Azure managed identity sign-ins | Automated workload access auditing |

Key filterable fields: `status/errorCode`, `riskLevelDuringSignIn`, `conditionalAccessStatus`, `mfaDetail`, `appDisplayName`, `ipAddress`, `location`.

#### Identity Protection Risk Detections — SOC 2 Relevance: CC7.2

Key types: `anonymizedIPAddress`, `impossibleTravel`, `maliciousIPAddress`, `unfamiliarFeatures`, `leakedCredentials`, `passwordSpray`, `tokenIssuerAnomaly`, `anomalousToken`.

### 2.2 Exchange Online Audit Events

#### Mailbox Audit Operations — SOC 2 Relevance: CC7.1, CC7.2, C1.1

| Logon Type | Key Operations |
|---|---|
| Owner | MailItemsAccessed*, Send, MoveToDeletedItems, SoftDelete, HardDelete, UpdateInboxRules |
| Delegate | MailItemsAccessed*, SendAs, SendOnBehalf, FolderBind |
| Admin | MailItemsAccessed*, Send, FolderBind |

*`MailItemsAccessed` requires E5/Audit Premium.

#### Exchange Admin Operations (critical for SOC 2)

| Operation | SOC 2 Use |
|---|---|
| New/Set/Remove-TransportRule | Mail flow rule changes |
| Set-Mailbox (forwarding) | Detect external mailbox forwarding (BEC indicator) |
| Add/Remove-MailboxPermission | Delegation changes |
| New/Set-InboxRule | Suspicious inbox rules (BEC indicator) |
| Set-AdminAuditLogConfig | Attempts to disable audit logging |

### 2.3 SharePoint / OneDrive Audit Events — SOC 2 Relevance: C1.1, C1.2, CC7.1

| Category | Key Operations | TSC Mapping |
|---|---|---|
| File Activities | FileAccessed, FileModified, FileDeleted, FileDownloaded, FileMalwareDetected | CC7.1 |
| Sharing | SharingSet, SharingInvitationCreated, AnonymousLinkCreated, SharingRevoked | C1.1 |
| Site Admin | SiteCollectionCreated, SiteCollectionAdminAdded, SiteDeleted | CC6.3 |
| Permissions | SitePermissionModified, AddedToGroup, RemovedFromGroup | CC6.3 |
| Sensitivity Labels | SensitivityLabelApplied, SensitivityLabelRemoved, SensitivityLabelChanged | C1.1 |

### 2.4 Microsoft Teams Audit Events — SOC 2 Relevance: CC6.1, CC7.1, C1.1

| Category | Key Operations |
|---|---|
| Team Lifecycle | TeamCreated, TeamDeleted, TeamSettingChanged |
| Membership | MemberAdded, MemberRemoved, MemberRoleChanged |
| Guest Access | GuestUserAdded, GuestSettingChanged |
| Apps | AppInstalled, AppUninstalled, BotAddedToTeam |

### 2.5 Microsoft Defender / Security Alerts — SOC 2 Relevance: CC7.2, CC7.3, CC7.4

| Source Product | Example Alert Types |
|---|---|
| Defender for Office 365 | Phishing detected, Malware campaign, Suspicious forwarding rules |
| Defender for Endpoint | Suspicious process, Ransomware activity, Credential access |
| Defender for Identity | Pass-the-hash, Brute force, Suspicious LDAP query |
| Defender for Cloud Apps | Impossible travel, Mass download, OAuth app anomaly |
| Entra ID Protection | Leaked credentials, Anonymous IP, Password spray |

Alert statuses: `new` → `inProgress` → `resolved`. Severity: `informational`, `low`, `medium`, `high`.

### 2.6 Purview / Compliance Events — SOC 2 Relevance: C1.1, C1.2

| Category | Key Operations |
|---|---|
| DLP | DlpRuleMatch, DlpRuleUndo, DlpRuleOverride |
| Sensitivity Labels | LabelApplied, LabelRemoved, MipAutoLabelExchangeItem |
| Retention | RetentionPolicyApplied, RetentionLabelApplied, DispositionReviewCompleted |
| eDiscovery | CaseCreated, SearchStarted, HoldCreated |

### 2.7 Intune / Endpoint Manager — SOC 2 Relevance: CC6.1, CC6.8

| Category | Key Operations |
|---|---|
| Device Compliance | DeviceComplianceStateChanged, NonCompliantDeviceDetected |
| Device Management | DeviceEnrolled, DeviceRetired, DeviceWiped |
| Configuration | ConfigurationPolicyCreated, ConfigurationPolicyModified |

---

## 3. API Endpoints & Permissions Reference

### Graph API Endpoints

| Log Type | Endpoint | Required Permissions | Rate Limit |
|---|---|---|---|
| Directory Audits | `GET /v1.0/auditLogs/directoryAudits` | `AuditLog.Read.All` | 5 req/10 sec |
| Sign-in Logs | `GET /v1.0/auditLogs/signIns` | `AuditLog.Read.All` | 5 req/10 sec |
| Non-interactive Sign-ins | `GET /beta/auditLogs/signIns?$filter=signInEventTypes/any(...)` | `AuditLog.Read.All` | 5 req/10 sec |
| Provisioning Logs | `GET /beta/auditLogs/provisioning` | `AuditLog.Read.All` | 5 req/10 sec |
| Risk Detections | `GET /v1.0/identityProtection/riskDetections` | `IdentityRiskEvent.Read.All` | Standard |
| Risky Users | `GET /v1.0/identityProtection/riskyUsers` | `IdentityRiskyUser.Read.All` | Standard |
| Security Alerts | `GET /v1.0/security/alerts_v2` | `SecurityAlert.Read.All` | Standard |
| Security Incidents | `GET /v1.0/security/incidents` | `SecurityIncident.Read.All` | Standard |
| UAL via Graph | `POST /v1.0/security/auditLog/queries` | `AuditLogsQuery.Read.All` | Async (job-based) |
| Secure Score | `GET /v1.0/security/secureScores?$top=1` | `SecurityEvents.Read.All` | Standard |
| Intune Devices | `GET /v1.0/deviceManagement/managedDevices` | `DeviceManagementManagedDevices.Read.All` | Intune limits |

### PowerShell Cmdlets (EXO / Purview)

| Cmdlet | Module | Key Parameters |
|---|---|---|
| `Search-UnifiedAuditLog` | ExchangeOnlineManagement | `-StartDate`, `-EndDate`, `-Operations`, `-RecordType`, `-ResultSize` (max 5000) |
| `Get-AdminAuditLogConfig` | ExchangeOnlineManagement | Returns `UnifiedAuditLogIngestionEnabled` |
| `Get-DlpCompliancePolicy` | Security & Compliance | `-DistributionDetail` |
| `Get-Label` | Security & Compliance | Sensitivity labels |
| `Get-RetentionCompliancePolicy` | Security & Compliance | `-DistributionDetail` |
| `Get-ProtectionAlert` | Security & Compliance | Alert policies |

### Throttling

All Graph endpoints return HTTP 429 with `Retry-After` header when throttled. Use exponential backoff. For bulk extraction, consider the Graph Audit Log Query API (`/security/auditLog/queries`) which runs asynchronously.

---

## 4. Graph API vs Unified Audit Log

This distinction is critical for automation design.

### Available ONLY via Graph API

- Sign-in logs (all 4 types)
- Risk detections and risky users
- Provisioning logs
- Security alerts and incidents
- Conditional Access evaluation details (embedded in sign-in logs)
- Intune device/compliance state
- Secure Score

### Available ONLY via UAL

- Exchange mailbox audit events (MailItemsAccessed, Send, etc.)
- SharePoint file/sharing operations (FileAccessed, SharingSet, etc.)
- Teams events (TeamCreated, MemberAdded, MessageSent, etc.)
- DLP policy matches (DlpRuleMatch)
- eDiscovery activities
- Retention label operations
- Power Platform / Power BI events

### Available via BOTH

- Entra ID directory audits (Graph: `/auditLogs/directoryAudits`, UAL: RecordType AzureActiveDirectory)
- Security alerts

### Bridging the Gap: Graph Audit Log Query API

`POST /v1.0/security/auditLog/queries` provides Graph-based access to the **full UAL dataset** without requiring Exchange Online PowerShell. It runs asynchronously (job-based), with results available 60-90 minutes after submission. This is the **recommended path for new automation** — it eliminates the EXO module dependency.

---

## 5. Data Retention Limits

### Unified Audit Log

| License | Default Retention | Custom Policies | Maximum |
|---|---|---|---|
| E3 / Business Premium | 180 days | Not available | 180 days |
| E5 (Audit Premium) | 1 year (Entra/Exchange/SPO); 180 days (others) | Up to 1 year any record type | 1 year |
| E5 + 10-Year Add-on | Same as E5 | Up to 10 years | 10 years |

### Entra ID Logs via Graph API

| License | Sign-in Logs | Directory Audit Logs |
|---|---|---|
| Entra ID Free | 7 days | 7 days |
| Entra ID P1/P2 | 30 days | 30 days |

**Critical**: To retain Entra logs beyond 30 days, you **must** stream to Log Analytics, Azure Storage, or a SIEM. This is separate from UAL retention.

### Security Alerts

- Microsoft Defender portal: 180 days
- Graph API: same as Defender portal

### SOC 2 Requirement

SOC 2 Type II audit periods are typically 3–12 months. **180-day E3 retention is borderline; 365-day E5 retention is recommended.** Your automation should export and archive to a separate store to guarantee retention independent of license tier.

---

## 6. Daily Monitoring Requirements by TSC

### CC6.x — Logical and Physical Access Controls

| Criterion | Daily Check | What It Proves |
|---|---|---|
| CC6.1 | MFA challenge outcomes in sign-in logs; CA policy evaluations | Authentication controls are enforced |
| CC6.1 | Service principal sign-in anomalies | Non-human identity access is tracked |
| CC6.2 | New user provisioning events; credential registrations | User onboarding follows controlled process |
| CC6.3 | Privileged role assignment changes; PIM activations | Least privilege is maintained; changes are logged |
| CC6.3 | Daily Global Admin count snapshot | Admin sprawl is detected early |
| CC6.6 | Guest invitations; external sharing events; location-based CA blocks | External access boundaries are enforced |
| CC6.8 | Defender malware detections; Safe Attachment/Link events | Anti-malware controls are active |

### CC7.x — System Operations / Monitoring / Incident Response

| Criterion | Daily Check | What It Proves |
|---|---|---|
| CC7.1 | UAL ingestion status; alert policy count; Secure Score | Monitoring infrastructure is functioning |
| CC7.2 | Failed sign-in aggregation (spike vs 30-day baseline); risk detections | Anomaly detection is operational |
| CC7.2 | Mailbox forwarding rule changes; new inbox rules | Email exfiltration vectors are monitored |
| CC7.3 | Alert triage rate (% moved from "new" within SLA); incident count | Events are being investigated |
| CC7.4 | Password resets after compromise; account disablements; CA emergency changes | Incident remediation actions are taken |

### C1.x — Confidentiality

| Criterion | Daily Check | What It Proves |
|---|---|---|
| C1.1 | Sensitivity label application events; auto-labeling activity | Data is being classified |
| C1.1 | External sharing of labeled content; anonymous link creation | Sharing of classified data is monitored |
| C1.2 | DLP policy match count; DLP override count | Data loss prevention is active |
| C1.2 | Retention policy application events | Data lifecycle is governed |

### CC3.x, CC5.x, CC8.x (Additional)

| Criterion | Weekly Check | What It Proves |
|---|---|---|
| CC3 (Risk Assessment) | Secure Score trend; new vulnerability alerts | Risk posture is continuously assessed |
| CC5 (Control Activities) | CA policy modifications; compliance scores | Control changes follow change management |
| CC8 (Change Management) | App consent grants; app registration changes; mailbox permission changes | Configuration changes are tracked |

---

## 7. Auditor Evidence Expectations

### What Auditors Want to See in Reports

**CC6 (Access Controls) — Monthly report with weekly snapshots:**
- All new user accounts created, with approval documentation references
- All privileged role assignments/removals, with business justification
- Access review completion percentage
- Active Global Admin count (target: 2–4)
- MFA registration coverage percentage
- Guest user inventory changes

**CC7 (Monitoring/Incident Response) — Daily and weekly:**
- Daily: Failed sign-in count with spike detection (vs 30-day baseline)
- Daily: New security alerts by severity
- Daily: Alert triage rate (% acknowledged within SLA)
- Weekly: MTTA (mean time to acknowledge) and MTTR (mean time to resolve)
- Weekly: Risky sign-in summary by risk level
- Weekly: Trend analysis showing no gaps in monitoring

**C1 (Confidentiality) — Weekly and monthly:**
- Weekly: DLP policy match count by policy with trend
- Weekly: Sensitivity label usage statistics
- Weekly: External sharing events for labeled content
- Monthly: Retention policy compliance

### The Critical Element: Evidence of Review

Generating reports is not enough. Auditors specifically look for:
- **Timestamped reviewer sign-off** (not just "report generated" — someone reviewed it)
- **Documented escalation** when thresholds are exceeded
- **Investigation notes** for anomalies (ticket references)
- **No gaps** in the reporting cadence over the full audit period

---

## 8. Alerting Thresholds

SOC 2 does not prescribe specific thresholds. Define and document your own, then tune over time. Recommended starting points:

| Alert Condition | Threshold | Severity | Response SLA |
|---|---|---|---|
| Failed logins from single user | 5+ in 10 minutes | Medium | 4 hours |
| Failed logins from single IP to multiple accounts | 20+ in 1 minute | High | 1 hour |
| Impossible travel detection | Any | High | 1 hour |
| New Global Admin assignment | Any | Critical | 30 minutes |
| MFA disabled for any user | Any | High | 1 hour |
| CA policy disabled or deleted | Any | Critical | 30 minutes |
| Mass file download | >100 files in 10 min | High | 1 hour |
| DLP match on "Highly Confidential" | Any | High | 2 hours |
| External sharing of Confidential file | Any | Medium | 4 hours |
| Mailbox forwarding to external domain | Any | High | 1 hour |
| Application consent for high-privilege scopes | Any | High | 2 hours |

**Tuning approach**: Start here, analyze 30 days of baseline data, adjust to 5–10 actionable alerts/week. Document all threshold changes with justification — auditors value evidence of intentional tuning.

---

## 9. Automation Platform Comparison

| Factor | Azure Automation (Runbooks) | Azure Functions | Logic Apps | Power Automate |
|---|---|---|---|---|
| **Best fit** | PowerShell config checks (matches existing scripts) | Custom logic, high-frequency | Multi-service orchestration, notifications | Citizen-developer dashboards, approvals |
| **Language** | PowerShell, Python | C#, JS, Python, PowerShell | Low-code (visual) | No-code/low-code |
| **Scheduling** | Built-in schedules | Timer triggers | Recurrence triggers | Recurrence triggers |
| **Graph API access** | Native via `Invoke-MgGraphRequest` | Via Graph SDK | HTTP connector | Graph connector (limited) |
| **Run duration limit** | 3 hrs (cloud), unlimited (hybrid) | 5–30 min (Consumption/Premium) | 90 days (Standard) | 5 min action timeout |
| **Auth** | Managed Identity (no secrets) | Managed Identity | Managed Identity | Connection references |
| **Cost (daily run)** | ~$1–3/mo (500 free min included) | ~$0–2/mo (1M free executions) | ~$1–5/mo | Included with M365 (standard connectors) |
| **Code reuse** | Direct reuse of existing PS1 scripts | Requires Function app wrapper | Requires HTTP calls | Requires rebuilding as flows |
| **SOC 2 audit trail** | Activity logs for runbook execution | App Insights | Run history per action | Run history in Dataverse |

---

## 10. Recommended Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     DAILY SCHEDULE (6 AM)                    │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              AZURE AUTOMATION ACCOUNT                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  System-Assigned Managed Identity                     │   │
│  │  (Graph permissions: AuditLog.Read.All,               │   │
│  │   Policy.Read.All, RoleManagement.Read.Directory,     │   │
│  │   SecurityEvents.Read.All, SecurityAlert.Read.All,    │   │
│  │   IdentityRiskEvent.Read.All, User.Read.All,          │   │
│  │   Reports.Read.All, AuditLogsQuery.Read.All)          │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Runbook 1: Get-SOC2SecurityControls.ps1     (config checks)│
│  Runbook 2: Get-SOC2ConfidentialityControls.ps1              │
│  Runbook 3: Get-SOC2AuditEvidence.ps1        (evidence)     │
│  Runbook 4: Get-SOC2ExtendedEvidence.ps1     (new — Phase 2)│
└────────────────────────────┬────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────────────┐
│ LOG ANALYTICS    │ │ AZURE BLOB   │ │ AZURE MONITOR ALERTS │
│ WORKSPACE        │ │ (cool tier)  │ │                      │
│                  │ │              │ │ Threshold rules →     │
│ • Custom tables  │ │ • CSV/JSON   │ │ Logic App →           │
│ • 365-day retain │ │ • 2-yr retain│ │ Teams / Email / ITSM  │
│ • KQL queries    │ │ • Immutable  │ │                      │
└────────┬─────────┘ └──────────────┘ └──────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                        │
│                                                              │
│  ┌──────────────┐  ┌──────────────────────────────────────┐ │
│  │ POWER BI     │  │ POWER APPS                           │ │
│  │              │  │                                      │ │
│  │ • Dashboards │  │ • Daily sign-off form                │ │
│  │ • Trends     │  │ • Exception tracking                 │ │
│  │ • KQL live   │  │ • Review log (auditor evidence)      │ │
│  │   connection │  │ • Dataverse tables                   │ │
│  └──────────────┘  └──────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Why Azure Automation as Primary

1. **Direct code reuse** — existing PS1 scripts run with minimal modification
2. **Managed Identity** — `Connect-MgGraph -Identity` requires zero stored secrets
3. **500 free minutes/month** — daily runs easily fit within free tier
4. **Built-in scheduling** — no external orchestration needed
5. **Activity logs** — every runbook execution is logged (SOC 2 audit trail)

### Authentication Setup

```powershell
# One-time setup (run as Global Admin):
# 1. Enable Managed Identity on the Automation Account
# 2. Grant Graph app permissions to the Managed Identity:

$miObjectId = "<automation-account-managed-identity-object-id>"
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

$permissions = @(
    "AuditLog.Read.All",
    "Policy.Read.All",
    "RoleManagement.Read.Directory",
    "SecurityEvents.Read.All",
    "SecurityAlert.Read.All",
    "IdentityRiskEvent.Read.All",
    "User.Read.All",
    "Reports.Read.All",
    "AuditLogsQuery.Read.All"
)

foreach ($perm in $permissions) {
    $appRole = $graphSP.AppRoles | Where-Object { $_.Value -eq $perm }
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $miObjectId `
        -PrincipalId $miObjectId `
        -ResourceId $graphSP.Id `
        -AppRoleId $appRole.Id
}
```

### Results Storage Strategy

| Tier | Purpose | Retention | Access |
|---|---|---|---|
| **Log Analytics** | Primary queryable store; Azure Monitor integration | 365+ days | Compliance team via Portal, Workbooks, KQL |
| **Blob Storage (cool)** | Long-term archive; tamper-evident | 2–3 years; immutable policies | On-demand auditor export |
| **Power BI** | Executive dashboard; trend visualization | Live connection | Published workspace with RLS |
| **SharePoint List** | Review sign-off tracking; exception log | Retention policies | Compliance team; Power Automate integration |

---

## 11. Power Platform Dashboard Option

### Power Apps Compliance Dashboard Design

**Tab 1 — Daily Status:**
- Traffic-light indicators (red/amber/green) per TSC category (CC6, CC7, C1)
- Today's alert count by severity
- Failed sign-in count with 7-day trend sparkline
- Alert triage rate (% acknowledged within SLA)

**Tab 2 — Control Health:**
- Table of all control checks (ControlId / ControlName / Status / LastRun)
- Last-pass and last-fail dates
- Drill-down to evidence details in Dataverse

**Tab 3 — Evidence Library:**
- Calendar view showing daily evidence collection dates
- Gaps highlighted in red (proves continuous cadence to auditors)
- Links to archived evidence in SharePoint / Blob Storage

**Tab 4 — Review Sign-off:**
- Daily sign-off form (date, reviewer, notes, exceptions)
- Historical sign-off log (this is what auditors most want to see)
- Escalation tracking for findings

**Dataverse Tables:**
- `ComplianceCheckResult` — daily control check outcomes
- `EvidenceSummary` — daily evidence collection summaries
- `ReviewSignOff` — compliance officer sign-off records
- `AlertTriage` — alert response tracking

### Power Automate's Role

Power Automate is the **glue**, not the compute engine:
- Triggered after Azure Automation runbook completes
- Parses results and writes to Dataverse tables
- Sends daily summary to Teams channel
- Triggers approval flows for exception handling

### Power Automate Limitations to Be Aware Of

| Limitation | Impact | Mitigation |
|---|---|---|
| 5-minute action timeout | Complex Graph queries may fail | Let Azure Automation do heavy lifting |
| 600 actions per run (standard) | Limits API calls per execution | Aggregate with OData filters server-side |
| HTTP connector requires Premium license | $15/user/month | Use per-flow licensing |
| No native PowerShell | Can't reuse scripts directly | Call Azure Automation as child runbook |

---

## 12. Gap Analysis vs Current Implementation

| Capability | Current State | Recommended Addition |
|---|---|---|
| CC6 config checks (S-01–S-05) | Implemented | Add CC6.6 (external access), CC6.8 (malware detection) |
| CC7 monitoring (S-06–S-08) | Implemented | Add CC7.4 (incident response execution evidence) |
| C1 confidentiality (C-01–C-07) | Implemented | Add sensitivity label usage metrics |
| Evidence: sign-ins, risks, alerts | E-01, E-02, E-04 implemented | Add E-03 (mailbox forwarding rules) |
| Evidence: roles, sharing, DLP | E-05, E-07, E-08 implemented | Add E-06 (CA policy changes), E-09 (app consent grants) |
| Non-interactive sign-ins | Not queried | Add service principal and managed identity sign-in checks |
| Teams audit events | Not collected | Add team creation, membership, guest access events |
| Exchange admin events | Not collected | Add transport rule, inbox rule, mailbox forwarding changes |
| Graph Audit Log Query API | Not used | Migrate UAL queries from EXO cmdlets to Graph async API |
| Automated scheduling | Manual execution only | Azure Automation with daily schedule |
| Results storage | CSV to local filesystem | Log Analytics + Blob archive |
| Alerting on thresholds | Not implemented | Azure Monitor alerts + Logic App notifications |
| Compliance sign-off workflow | Not implemented | Power Apps + Power Automate |
| Trend analysis / dashboarding | Not implemented | Power BI connected to Log Analytics |
| Provable daily cadence | Not provable (manual) | Automated runs with execution logs |

---

## 13. Implementation Phases

### Phase 1: Automate Existing Scripts (Weeks 1–2)

- [ ] Create Azure Automation Account with System-Assigned Managed Identity
- [ ] Grant Graph API application permissions to Managed Identity
- [ ] Import existing 3 SOC 2 scripts as runbooks
- [ ] Modify scripts to use `Connect-MgGraph -Identity` (Managed Identity auth)
- [ ] Create Log Analytics workspace; add output module to push results
- [ ] Configure daily schedule (6:00 AM)
- [ ] Verify first 7 days of automated runs

### Phase 2: Close Evidence Gaps (Weeks 3–4)

- [ ] Implement E-03: Mailbox forwarding rule changes
- [ ] Implement E-06: Conditional Access policy modifications
- [ ] Implement E-09: Application consent grants and credential changes
- [ ] Add non-interactive and service principal sign-in queries
- [ ] Add Teams audit event collection
- [ ] Migrate UAL queries from `Search-UnifiedAuditLog` to Graph Audit Log Query API
- [ ] Add CC6.6 and CC6.8 configuration checks

### Phase 3: Alerting (Weeks 5–6)

- [ ] Define and document alerting thresholds (with baseline from Phase 1 data)
- [ ] Create Azure Monitor alert rules for critical thresholds
- [ ] Build Logic App for notification routing (Teams channel + email DL)
- [ ] Add escalation logic for critical alerts (Global Admin change, CA policy deletion)
- [ ] Test alert pipeline end-to-end

### Phase 4: Dashboard & Sign-off (Weeks 7–10)

- [ ] Create Dataverse tables for compliance data
- [ ] Build Power Automate flow to parse runbook output → Dataverse
- [ ] Build Power BI dashboard (connected to Log Analytics)
- [ ] Build Power Apps compliance officer sign-off workflow
- [ ] Create daily summary notification to Teams
- [ ] Configure Row-Level Security on Power BI for compliance team

### Phase 5: Tuning & Audit Prep (Weeks 11–12)

- [ ] Analyze 30+ days of collected data for threshold tuning
- [ ] Adjust alerting thresholds; document justification for each change
- [ ] Verify no gaps in daily cadence over full period
- [ ] Create auditor-ready evidence export package
- [ ] Dry-run with auditor checklist
- [ ] Document runbook execution procedures and escalation paths

---

## Appendix: Evidence Retention Quick Reference

| Evidence Type | Minimum | Recommended | Notes |
|---|---|---|---|
| Audit log raw data | 365 days | 2 years | Covers audit period + preparation overlap |
| Daily monitoring reports | 365 days | 2 years | Must cover full observation window |
| Alert investigation records | 365 days | 3 years | Needed for incident follow-up |
| Access review records | 365 days | 3 years | Proves quarterly review cadence |
| Configuration change logs | 365 days | 2 years | CC8 change management evidence |
| Incident response docs | 3 years | 5 years | Legal and regulatory overlap |
