# Collector Output Standardization

> **Date**: 2026-03-11
> **Scope**: Standardize all 5 security config collectors to match EXO's clear pass/fail + actionable remediation pattern

## Overview

Community feedback identified that the Exchange Online collector sets the standard for clarity: binary pass/fail status with copy-paste PowerShell commands in remediation. The other 4 collectors (Entra, Defender, SharePoint, Teams) are inconsistent — overusing "Review", lacking automation commands, and providing UI-only remediation.

This effort standardizes all collectors to the EXO pattern, introduces a new "Info" status for non-actionable checks, assigns CheckIds to all unmapped checks, and adds PowerShell commands to every remediation field.

## The EXO Standard

Every check follows this pattern:
1. **Status**: Pass/Fail for binary checks. Warning for degraded-but-not-broken. Review ONLY when automated pass/fail is genuinely impossible.
2. **Remediation format**: `"Run: <PowerShell command>. <UI path as fallback>."`
3. **Command first**: The automation command leads, UI navigation is secondary context.

## New Status: Info

A new "Info" status for checks that report useful data but are not pass/fail security assessments.

- **HTML badge**: grey (`background: #f3f4f6; color: #6b7280;`, dark: `background: #374151; color: #9ca3af;`)
- **XLSX formatting**: grey text on light grey background
- **Scoring**: excluded from pass rate calculations in both HTML donut chart and XLSX summary sheet
- **CSV**: appears in output with Status = "Info"

### Checks Classified as Info

| Collector | Setting | CheckId | Previous Status |
|-----------|---------|---------|-----------------|
| Entra | Guest User Count | ENTRA-GUEST-003 | Review |
| Entra | Total CA Policies | ENTRA-CA-002 | Warning |
| SharePoint | Mac Sync App Enabled | SPO-SYNC-002 | Review |
| SharePoint | Loop Components Enabled | SPO-LOOP-001 | Review |
| SharePoint | OneDrive Loop Sharing | SPO-LOOP-002 | Review |
| Teams | Teams Workload Active | TEAMS-INFO-001 | Pass |

## New CheckId Assignments

| Collector | Setting | CheckId |
|-----------|---------|---------|
| Entra | Security Defaults Enabled | ENTRA-SECDEFAULT-001 |
| Entra | Users Can Register Applications | ENTRA-APPREG-001 |
| Entra | Smart Lockout Threshold | ENTRA-PASSWORD-003 |
| Entra | Total CA Policies | ENTRA-CA-002 |
| Entra | Enabled CA Policies | ENTRA-CA-003 |
| Entra | Guest User Count | ENTRA-GUEST-003 |
| SharePoint | Mac Sync App Enabled | SPO-SYNC-002 |
| SharePoint | Loop Components Enabled | SPO-LOOP-001 |
| SharePoint | OneDrive Loop Sharing | SPO-LOOP-002 |
| Teams | Chat Resource-Specific Consent | TEAMS-APPS-001 |
| Teams | Teams Workload Active | TEAMS-INFO-001 |

All new CheckIds follow the existing `{COLLECTOR}-{AREA}-{NNN}` convention and require corresponding entries in `controls/registry.json` with framework mappings.

## Severity Change Audit

### Status Definitions (Tightened)

| Status | Meaning | Use When |
|--------|---------|----------|
| Pass | Meets benchmark | Check passes the expected condition |
| Fail | Violates benchmark | CIS says "Ensure" and the tool can determine the setting is wrong |
| Warning | Degraded security | Setting is suboptimal but not a hard violation, or org context may vary |
| Review | Cannot determine automatically | Automated pass/fail is genuinely impossible (licensing, org-specific policy) |
| Info | Informational | Data point with no right/wrong answer — excluded from scoring |

### Entra — Severity Changes

| # | CheckId | Setting | Current | Proposed | Rationale |
|---|---------|---------|---------|----------|-----------|
| 1 | ENTRA-SECDEFAULT-001 | Security Defaults Enabled | Review | Fail | Binary — enabled or not. CIS 1.1.1 "Ensure" |
| 2 | ENTRA-CONSENT-001 | User Consent for Applications | Warning | Fail | CIS 2.1.4 "Ensure" — user consent is exploitable |
| 3 | ENTRA-APPREG-001 | Users Can Register Applications | Warning | Fail | CIS 2.1.5 "Ensure" — unrestricted registration |
| 4 | ENTRA-GROUP-001 | Users Can Create Security Groups | Review | Warning | Governance risk, determinable, but org-specific |
| 5 | ENTRA-CONSENT-002 | Admin Consent Workflow Enabled | Warning | Keep Warning | Best practice, not hard violation |
| 6 | ENTRA-MFA-001 | Auth Method Registration Campaign | Review | Warning | Determinable — campaign is enabled or not |
| 7 | ENTRA-PASSWORD-002 | Custom Banned Password Count | Review | Warning | Empty list is determinable |
| 8 | ENTRA-PASSWORD-003 | Smart Lockout Threshold | Review | Keep Review | Optimal threshold is org-specific |
| 9 | ENTRA-PASSWORD-001 | Password Expiration | Review | Fail | CIS 1.3.1 "Ensure" — measurable |
| 10 | ENTRA-GUEST-001 | Guest User Access Restriction | Review | Warning | Determinable but "most restrictive" may not suit every org |
| 11 | ENTRA-GUEST-002 | Guest Invitation Policy | mixed | Keep as-is | Already has nuanced logic |
| 12 | ENTRA-CA-003 | Enabled CA Policies | Warning | Warning | Correct — enabled count matters |

### Defender — Severity Changes

| # | CheckId | Setting | Current | Proposed | Rationale |
|---|---------|---------|---------|----------|-----------|
| 1 | DEFENDER-ANTIPHISH-001 | Phishing Threshold | Warning | Fail | CIS 2.1.2 "Ensure" threshold >= 2 |
| 2 | DEFENDER-ANTIPHISH-001 | Targeted User Protection | Review | Warning | Determinable (enabled/disabled) |
| 3 | DEFENDER-ANTIPHISH-001 | Targeted Domain Protection | Review | Warning | Determinable (enabled/disabled) |
| 4 | DEFENDER-ANTIPHISH-001 | Honor DMARC Policy | Warning | Fail | CIS 2.1.2 "Ensure" — binary |
| 5 | DEFENDER-ANTIPHISH-001 | First Contact Safety Tips | Review | Warning | Determinable |
| 6 | DEFENDER-ANTISPAM-001 | Spam Action | Review | Warning | Determinable |
| 7 | DEFENDER-ANTISPAM-001 | Spam ZAP | Warning | Fail | CIS 2.1.6 "Ensure" |
| 8 | DEFENDER-ANTIMALWARE-001 | Common Attachment Filter | Warning | Fail | CIS 2.1.3 "Ensure" — binary |
| 9 | DEFENDER-ANTIMALWARE-002 | Internal Sender Admin Notifications | Review | Warning | Determinable |
| 10 | DEFENDER-SAFELINKS-001 | Track User Clicks | Review | Warning | Binary |
| 11 | DEFENDER-SAFELINKS-001 | Enable for Internal Senders | Review | Warning | Binary |
| 12 | DEFENDER-SAFELINKS-001 | Wait for URL Scan | Review | Warning | Binary |
| 13 | DEFENDER-SAFEATTACH-001 | Redirect to Admin | Review | Warning | Determinable |
| 14 | DEFENDER-OUTBOUND-001 | BCC on Suspicious Outbound | Review | Warning | Determinable |
| 15 | DEFENDER-OUTBOUND-001 | Notify Admins of Outbound Spam | Review | Warning | Determinable |

### SharePoint — Severity Changes

| # | CheckId | Setting | Current | Proposed | Rationale |
|---|---------|---------|---------|----------|-----------|
| 1 | SPO-SESSION-001 | Idle Session Timeout | Review | Warning | Determinable |
| 2 | SPO-SHARING-003 | Sharing Domain Restriction | Review | Keep Review | Org-specific |
| 3 | SPO-SHARING-007 | Default Sharing Link Permission | Review | Warning | "Edit" default is determinable and riskier |

### Teams — Severity Changes

| # | CheckId | Setting | Current | Proposed | Rationale |
|---|---------|---------|---------|----------|-----------|
| 1 | TEAMS-MEETING-001 | Anonymous Users Can Join Meeting | Warning | Fail | CIS 8.5.1 "Ensure" — binary |

## Remediation Command Standards

### Command Sources by Collector

| Collector | Module | Example |
|-----------|--------|---------|
| Entra | Microsoft.Graph.* | `Update-MgPolicyAuthorizationPolicy` |
| Defender | ExchangeOnlineManagement | `Set-AntiPhishPolicy`, `Set-HostedContentFilterPolicy` |
| SharePoint | Microsoft.Online.SharePoint.PowerShell | `Set-SPOTenant` |
| Teams | MicrosoftTeams | `Set-CsTeamsMeetingPolicy` |

### Rules

- **Command first, UI second**: `"Run: Set-AntiPhishPolicy -PhishThresholdLevel 2. Security admin center > Anti-phishing > Edit policy."`
- **No hardcoded -Identity**: Use generic form — inform, don't prescribe
- **Info checks**: Descriptive text instead of commands (e.g., "Informational — review based on organizational requirements.")
- **Graph PowerShell only** for Entra (no REST endpoints) — the audience is PowerShell users

## Files Modified

| File | Changes |
|------|---------|
| `Entra/Get-EntraSecurityConfig.ps1` | 12 severity changes, 19 remediation rewrites, 6 new CheckIds |
| `Security/Get-DefenderSecurityConfig.ps1` | 11 severity changes, 31 remediation rewrites |
| `Collaboration/Get-SharePointSecurityConfig.ps1` | 3 severity changes, 6 remediation additions, 3 new CheckIds |
| `Collaboration/Get-TeamsSecurityConfig.ps1` | 1 severity change, 3 remediation additions, 2 new CheckIds |
| `controls/registry.json` | 11 new entries with framework mappings |
| `Common/Export-AssessmentReport.ps1` | Info badge style, exclude Info from scoring |
| `Common/Export-ComplianceMatrix.ps1` | Info conditional formatting, exclude from pass rate |
| `README.md` | Update status descriptions to include Info, document remediation command style |

## What Does NOT Change

- `Exchange-Online/Get-ExoSecurityConfig.ps1` — untouched (it's the standard)
- CheckId format convention — same `{COLLECTOR}-{AREA}-{NNN}`
- CSV column structure — no new columns
- HTML report layout — same structure, new grey badge only
- Registry schema — same structure

## Version

0.5.0 → **0.6.0** (new feature: Info status + standardized remediation)
