# M365-Assess: Daren9m → SelvageLabs Org Migration Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update all GitHub URLs and org references from `Daren9m` to `SelvageLabs` after repository transfer.

**Architecture:** Global find-and-replace for GitHub URLs. Author attribution fields (`.NOTES Author:`) are personal credit and should NOT change. CODEOWNERS uses GitHub usernames (not org names), so it stays as `@Daren9m`.

**Scope:** 25 files, 33 references. No submodules.

---

## What Changes vs What Stays

| Reference Type | Example | Action |
|---------------|---------|--------|
| GitHub repo URLs | `github.com/Daren9m/M365-Assess` | **Change** → `SelvageLabs/M365-Assess` |
| `.NOTES Author:` | `Author: Daren9m` | **Keep** — personal attribution |
| CODEOWNERS | `@Daren9m` | **Keep** — GitHub username, not org |
| LICENSE copyright | `Copyright (c) 2026 Daren9m` | **Decision needed** — personal or org? |
| Module manifest Author | `Author = 'Daren9m'` | **Decision needed** — personal or org? |

---

## Chunk 1: URL Updates

### Task 1: Update GitHub URLs in documentation and config

**Files to modify (URLs only):**
- `M365-Assess.psd1` (lines 91-92: LicenseUri, ProjectUri)
- `README.md` (lines 30, 66, 277)
- `CONTRIBUTING.md` (line 9)
- `SECURITY.md` (line 20)
- `Invoke-M365Assessment.ps1` (line 3609: HTML report branding)
- `docs/sample-report/_Example-Report.html` (branding links)
- `docs/superpowers/specs/2026-03-13-v080-cis-gap-closure-design.md` (line 6)

- [ ] **Step 1: Replace all GitHub URLs**

In each file listed above, replace:
- `github.com/Daren9m/M365-Assess` → `github.com/SelvageLabs/M365-Assess`

Use global find-and-replace across all file types:
```bash
grep -rl "Daren9m/M365-Assess" . --include="*.md" --include="*.ps1" --include="*.psd1" --include="*.html" --include="*.txt" | head -20
```

- [ ] **Step 2: Verify no stale URLs remain**

```bash
grep -r "Daren9m" . --include="*.md" --include="*.psd1" --include="*.html" --include="*.txt" | grep -v "Author" | grep -v "CODEOWNERS" | grep -v "Copyright"
```

Expected: No output (all URL references updated, author/copyright lines excluded).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: update GitHub URLs from Daren9m to SelvageLabs org"
```

---

### Task 2: Update ownership fields (decision required)

**Files (only if owner decides to change attribution to org):**
- `M365-Assess.psd1` (line 8: Author, line 10: Copyright)
- `LICENSE` (line 3: Copyright)

- [ ] **Step 1: If owner wants org attribution, update these fields**

- `Author = 'Daren9m'` → `Author = 'SelvageLabs'`
- `Copyright (c) 2026 Daren9m` → `Copyright (c) 2026 SelvageLabs`

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: update copyright attribution to SelvageLabs"
```

---

## Post-Implementation Notes

### Files intentionally NOT changed
- `.github/CODEOWNERS` — uses GitHub username `@Daren9m`, not org name
- All `.NOTES Author: Daren9m` in PowerShell scripts — personal attribution
- `Setup/Add-M365AssessmentPermissions.txt` — author reference
