# Backlog Grooming Design - 2026-03-14

## Context

Grooming session to identify issues/enhancements in the M365-Assess repo, create GitHub issues, and organize them into milestones.

## Current State (Pre-Grooming)

- **Version:** 0.8.1 in codebase (milestones v0.8.2 and v0.8.3 were organizational labels, not version bumps)
- **Open issues:** #66 (Power BI/CIS), #67 (frameworks), #83 (CheckID sync), #84 (auth)
- **Problem:** Duplicate v0.9.0 milestones (#3 and #6), no tracking for org migration, codebase bugs untracked, testing policy outdated

## Approach Selected

**Approach B: Consolidate into fewer releases.** Bundle housekeeping and hardening into one pre-v0.9.0 release (v0.8.4) so v0.9.0 stays purely feature-focused.

### Rationale

- One version bump covers all prep work (vs. two thin milestones)
- Cleaner release history
- Sets a solid foundation before the feature-heavy v0.9.0
- 30-file version bump is annoying but scripted

## Actions Taken

### Milestone Cleanup

| Action | Result |
|--------|--------|
| Moved #66, #84 from milestone #6 to #3 | Canonical v0.9.0 is now milestone #3 |
| Deleted milestone #6 (duplicate) | Removed |
| Created milestone #7 "v0.8.4 - Hardening & Housekeeping" | New milestone |

### Issues Created

| Issue | Type | Title | Milestone |
|-------|------|-------|-----------|
| #88 | bug | fix: unsafe array access in Get-EntraSecurityConfig.ps1 | v0.8.4 |
| #89 | bug | fix: unsafe array access in Export-AssessmentReport.ps1 | v0.8.4 |
| #90 | enhancement | chore: track org attribution migration to SelvageLabs | v0.8.4 |
| #91 | enhancement | chore: update CLAUDE.md testing policy to include Pester | v0.8.4 |
| #92 | enhancement | chore: clean up duplicate v0.9.0 milestones | v0.8.4 (closed) |
| #93 | enhancement | test: expand Pester coverage to all security collectors | v0.8.4 |
| #94 | documentation | docs: add CHANGELOG entries for work since v0.8.1 | v0.8.4 |

## Final Milestone Map

| Milestone | Status | Open | Closed | Theme |
|-----------|--------|------|--------|-------|
| v0.8.1 - Polish & Foundation | Closed | 0 | 6 | -- |
| v0.8.2 - CI & Quality | Closed | 0 | 5 | -- |
| v0.8.3 - Report & UX Polish | Closed | 0 | 4 | -- |
| v0.8.4 - Hardening & Housekeeping | **Open** | 6 | 1 | Bugs, tests, docs, chores |
| v0.9.0 - Power BI & 100% CIS | Open | 2 | 3 | Features (#66, #84) |
| v1.0.0 - Native Frameworks | Open | 1 | 0 | Features (#67) |
| *(unscoped)* | -- | 1 | -- | External (#83 CheckID sync) |

## Decisions Made

1. **Milestone organization:** Approach B (consolidate housekeeping into v0.8.4)
2. **Duplicate v0.9.0:** Merge onto #3 (better description), delete #6
3. **Org attribution:** Track with issue, bundle into next version bump
4. **CHANGELOG:** v0.8.2/v0.8.3 were milestone labels only; consolidate entries when v0.8.4 version bump happens
5. **Bug fixes:** Create issues and scope to v0.8.4 (cheap defensive fixes)
6. **Test expansion:** Single umbrella issue for all 8 remaining collector test suites
7. **Testing policy:** Update CLAUDE.md to remove "on demand only" Pester stance; tests are now part of standard workflow
