# M365-Assess: PowerPoint Deck Export Plan

> **Date**: March 2026
> **Scope**: Add a branded PowerPoint (.pptx) deck as an optional report output alongside the existing HTML report
> **Technology**: OpenXML SDK via PowerShell (no COM/Office dependency)
> **Target**: Consultant-ready executive briefing deck generated from the same assessment data

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Slide Deck Structure](#3-slide-deck-structure)
4. [Technical Approach](#4-technical-approach)
5. [Data Flow](#5-data-flow)
6. [Slide Templates & Branding](#6-slide-templates--branding)
7. [Chart & Visual Strategy](#7-chart--visual-strategy)
8. [Implementation Phases](#8-implementation-phases)
9. [File Structure](#9-file-structure)
10. [Risk & Mitigations](#10-risk--mitigations)
11. [Future Enhancements](#11-future-enhancements)

---

## 1. Executive Summary

### Why PowerPoint?

The HTML report is comprehensive but serves a different audience. Consultants delivering findings to C-level stakeholders need a presentation-ready deck they can walk through in a meeting, annotate, and leave behind as a branded deliverable.

| Capability | HTML Report | PowerPoint Deck |
|-----------|------------|----------------|
| **Audience** | Technical reviewers, compliance teams | Executives, board members, CISOs |
| **Depth** | Full detail — every control, every table | Executive summary — key metrics and risk areas |
| **Customization** | View in browser, print to PDF | Edit slides, add client branding, presenter notes |
| **Delivery** | Self-contained file, browser-based | Meeting presentation, email attachment |
| **Data density** | High — 300+ row tables, 140 CIS controls | Low — top findings, donut charts, score cards |

### Design Principles

1. **Executive-focused** — Not a dump of every table. Curated slides highlighting risk posture, key gaps, and remediation priorities
2. **Brandable** — Slide master with configurable colors, logo placement, and fonts so consultants can apply their firm's branding
3. **No Office dependency** — Pure OpenXML generation via .NET/PowerShell. Works on Linux, in containers, in Azure Functions
4. **Same data, different lens** — Consumes the same assessment CSVs and summary data as the HTML report. No separate collection step

---

## 2. Architecture Overview

### Integration Point

The PowerPoint export will be a new function called from `Invoke-M365Assessment.ps1` after the HTML report is generated:

```
Invoke-M365Assessment.ps1
  ├─ ... collectors ...
  ├─ Export-AssessmentReport.ps1    → _Assessment-Report.html
  └─ Export-AssessmentDeck.ps1     → _Assessment-Deck.pptx  (NEW)
```

### Module Dependencies

```
DocumentFormat.OpenXml (NuGet)     — OpenXML SDK for .pptx generation
  └─ No COM, no Office installation required
  └─ Cross-platform (.NET 6+/8+)
  └─ MIT licensed
```

**Alternative considered**: `PresentationML` raw XML manipulation (no SDK). Rejected — too error-prone for chart generation and slide master support. The SDK provides typed classes and validation.

### Invocation

```powershell
# New parameter on Invoke-M365Assessment.ps1
[switch]$IncludeDeck

# Called after HTML report
if ($IncludeDeck) {
    $deckParams = @{ AssessmentFolder = $assessmentFolder }
    if ($TenantId) { $deckParams['TenantName'] = $TenantId }
    & "$PSScriptRoot\Common\Export-AssessmentDeck.ps1" @deckParams
}
```

---

## 3. Slide Deck Structure

### Slide Sequence (Target: 12-18 slides)

| # | Slide | Content | Data Source |
|---|-------|---------|-------------|
| 1 | **Title Slide** | M365 Assessment Report, tenant name, date, version, logo | `_Assessment-Summary.csv`, tenant CSV |
| 2 | **Agenda / TOC** | Numbered list of sections covered | Section list from summary |
| 3 | **Executive Overview** | Collector completion donut, total sections, total CIS controls assessed | Summary stats |
| 4 | **Risk Posture** | Large pass/fail/warning donut chart, key numbers (pass %, fail count) | CIS findings aggregated |
| 5 | **Top Findings** | Table of top 10 highest-severity failed controls with remediation | `_Assessment-Issues.log` + CIS CSVs |
| 6 | **Identity & Access** | MFA adoption %, SSPR enrollment %, admin role count, conditional access count | Entra CSVs |
| 7 | **Email Security** | Secure Score %, SPF/DKIM/DMARC pass rates, transport rules count | EXO CSVs |
| 8 | **Defender & DLP** | Defender policies enabled/disabled, DLP policy count, improvement actions | Security CSVs |
| 9 | **Collaboration** | SharePoint external sharing level, Teams guest access, OneDrive sharing | Collaboration CSVs |
| 10 | **Hybrid Identity** | Sync health status, last sync time, AAD Connect version | Hybrid CSVs |
| 11 | **Compliance Matrix** | Framework coverage heatmap — CIS-E3, CIS-E5, NIST, ISO, etc. | `framework-mappings.csv` + CIS results |
| 12 | **Remediation Roadmap** | Prioritized remediation grouped by effort (Quick Wins / Medium / Strategic) | Issues log severity + remediation text |
| 13 | **Appendix: Collector Status** | Table showing all collectors with status badges (Complete/Skipped/Failed) | `_Assessment-Summary.csv` |
| 14 | **Thank You / Contact** | Consultant contact info placeholder, next steps | Static template |

**Conditional slides**: Slides 6-10 are only included if the corresponding section was collected (not skipped). If a section was skipped, the slide is omitted rather than showing empty data.

---

## 4. Technical Approach

### Option A: OpenXML SDK (Recommended)

Use `DocumentFormat.OpenXml` NuGet package loaded into PowerShell:

```powershell
# Load OpenXML SDK assembly
Add-Type -Path "$PSScriptRoot\lib\DocumentFormat.OpenXml.dll"

# Or install from NuGet at runtime
if (-not (Get-Package DocumentFormat.OpenXml -ErrorAction SilentlyContinue)) {
    Install-Package DocumentFormat.OpenXml -Source nuget.org -Scope CurrentUser
}
```

**Pros**: Typed API, chart support, slide master/layout support, validation
**Cons**: ~5MB dependency, learning curve for PresentationML object model

### Option B: Template-based (Hybrid)

Ship a `.pptx` template file with pre-built slide layouts. At runtime, clone slides from the template, find placeholder shapes by name, and replace text/images:

```powershell
# Clone template, replace placeholders
$template = [DocumentFormat.OpenXml.Packaging.PresentationDocument]::Open($templatePath, $true)
# Find shape by name, replace text
$shape = Get-SlideShape -Slide $slide -Name 'TenantName'
$shape.TextBody.Text = $TenantName
```

**Pros**: Visual design done in PowerPoint (easier to brand), simpler code
**Cons**: Template must be maintained, harder to add/remove conditional slides

### Recommendation: Option B (Template-based)

The template approach is significantly simpler for consultants who want to customize branding — they edit the template in PowerPoint like any other deck. The code only needs to:
1. Clone the template
2. Find named placeholders and replace text/values
3. Insert chart data into pre-positioned chart placeholders
4. Remove slides for skipped sections
5. Save as new file

---

## 5. Data Flow

```
Assessment Folder
  ├─ _Assessment-Summary.csv ──────┐
  ├─ _Assessment-Issues.log ───────┤
  ├─ 01-Tenant-Info.csv ───────────┤
  ├─ Entra/*.csv ──────────────────┤
  ├─ EXO/*.csv ────────────────────┤     Export-AssessmentDeck.ps1
  ├─ Security/*.csv ───────────────┼──→  (parse CSVs, compute metrics,
  ├─ Collaboration/*.csv ──────────┤      populate template placeholders)
  ├─ Hybrid/*.csv ─────────────────┤          │
  └─ Common/framework-mappings.csv ┘          ▼
                                      _Assessment-Deck.pptx
```

### Shared Logic with HTML Report

Several metric calculations already exist in `Export-AssessmentReport.ps1`:
- CIS pass/fail/warning counts
- Framework score computation
- MFA/SSPR percentages
- Secure Score extraction
- DNS authentication pass rates

**Strategy**: Extract shared metric computation into a helper `Get-AssessmentMetrics.ps1` that both the HTML report and PowerPoint deck can call. This avoids duplicating 200+ lines of metric logic.

```powershell
# Common/Get-AssessmentMetrics.ps1
function Get-AssessmentMetrics {
    [CmdletBinding()]
    param([string]$AssessmentFolder)

    # Returns a hashtable with all computed metrics
    @{
        TenantName       = $tenantName
        AssessmentDate   = $assessmentDate
        Collectors       = @{ Complete = $n; Skipped = $n; Failed = $n }
        CIS              = @{ Pass = $n; Fail = $n; Warning = $n; Total = $n }
        MFA              = @{ RegisteredPct = $n; CapableUsers = $n }
        SSPR             = @{ EnrolledPct = $n }
        SecureScore      = @{ CurrentPct = $n }
        DNS              = @{ SPF = $n; DKIM = $n; DMARC = $n }
        Frameworks       = @{ ... }  # per-framework scores
        TopFindings      = @(...)    # top 10 highest-severity failures
        Sections         = @(...)    # which sections were collected
    }
}
```

---

## 6. Slide Templates & Branding

### Template File

Ship `Common/templates/assessment-deck-template.pptx` with:

| Element | Details |
|---------|---------|
| **Slide Master** | Clean corporate layout, 16:9 aspect ratio |
| **Color Scheme** | Uses theme colors (accent1-6) so consultants can change the palette in one place |
| **Font Theme** | Inter / Segoe UI (matches HTML report) |
| **Logo Placeholder** | Named shape `LogoPlaceholder` on title slide and slide master footer |
| **Slide Layouts** | Title, Section Header, Content, Two-Column, Chart, Table, Blank |

### Named Placeholders Convention

Every data-driven element uses a named shape:

```
{{TenantName}}          → Tenant display name
{{AssessmentDate}}       → Assessment date string
{{AssessmentVersion}}    → Suite version (e.g., 0.4.0)
{{PassCount}}            → CIS pass count
{{FailCount}}            → CIS fail count
{{MfaPct}}               → MFA registration percentage
{{SecureScorePct}}       → Defender Secure Score %
{{ChartPlaceholder:X}}   → Chart data injection point
```

### Consultant Customization

Consultants customize branding by:
1. Opening `assessment-deck-template.pptx` in PowerPoint
2. Editing the Slide Master (View → Slide Master)
3. Changing theme colors, fonts, and logo
4. Saving — all future decks inherit the branding

---

## 7. Chart & Visual Strategy

### Donut Charts

The HTML report uses inline SVG donuts. For PowerPoint, two options:

**Option A: OpenXML Charts (Native)**
- Insert actual PowerPoint chart objects (Doughnut chart type)
- Fully editable in PowerPoint, animations work
- More complex to generate programmatically
- Data is embedded in the chart's Excel worksheet

**Option B: EMF/PNG Images**
- Render donut charts as images and insert as picture shapes
- Simpler generation (can reuse SVG logic → convert to image)
- Not editable in PowerPoint
- Requires image rendering capability (System.Drawing or SkiaSharp)

**Recommendation**: Option A for key charts (risk posture donut, MFA donut) and table shapes for everything else. Native charts are expected in a professional deck.

### Tables

Use PowerPoint table shapes (not images of tables):
- Top Findings table (slide 5)
- Collector Status table (appendix)
- Framework heatmap (use colored table cells)

### Status Indicators

Use colored shapes (circles/rectangles) with theme colors:
- Green (#2ecc71) → Pass
- Red (#e74c3c) → Fail
- Orange (#f39c12) → Warning
- Blue (#3498db) → Info

---

## 8. Implementation Phases

### Phase 1: Foundation (MVP)

**Goal**: Generate a basic branded deck with text-only slides

| Task | Details |
|------|---------|
| Add OpenXML SDK dependency | `lib/` folder or NuGet install script |
| Create `Export-AssessmentDeck.ps1` | Script skeleton with CmdletBinding, parameters, help |
| Create template `.pptx` | Slide master, 14 slide layouts with named placeholders |
| Implement placeholder replacement | Find shapes by name, replace `{{token}}` with values |
| Implement conditional slide removal | Remove slides for skipped sections |
| Extract `Get-AssessmentMetrics.ps1` | Shared metric computation helper |
| Wire into `Invoke-M365Assessment.ps1` | `-IncludeDeck` switch parameter |
| Output `_Assessment-Deck.pptx` | Save to assessment folder alongside HTML |

**Deliverable**: A deck with correct text on every slide, no charts yet.

### Phase 2: Charts & Visuals

**Goal**: Add native PowerPoint charts and visual elements

| Task | Details |
|------|---------|
| Donut chart generation | Risk posture, MFA adoption, collector completion |
| Table generation | Top findings, collector status, framework heatmap |
| Status indicator shapes | Colored dots/badges for pass/fail/warning |
| Presenter notes | Auto-generated talking points per slide |

**Deliverable**: A visually complete deck with charts, tables, and status indicators.

### Phase 3: Polish & Customization

**Goal**: Professional finish and consultant workflow

| Task | Details |
|------|---------|
| Transition animations | Subtle slide transitions (fade) |
| Hyperlinks | Link from TOC slide to section slides |
| Custom branding docs | README section on how to customize the template |
| Logo injection | Insert base64/file logo into template placeholder |
| PDF export option | Optional conversion of .pptx → .pdf via LibreOffice CLI |

**Deliverable**: A production-ready, consultant-deliverable deck.

---

## 9. File Structure

### New Files

```
Common/
├─ Export-AssessmentDeck.ps1          # Main deck generation script
├─ Get-AssessmentMetrics.ps1         # Shared metric computation (extracted from HTML report)
├─ templates/
│   └─ assessment-deck-template.pptx # Branded slide template (16:9)
└─ lib/
    └─ DocumentFormat.OpenXml.dll    # OpenXML SDK assembly (or NuGet-managed)
```

### Modified Files

```
Invoke-M365Assessment.ps1            # Add -IncludeDeck switch, call Export-AssessmentDeck
Common/Export-AssessmentReport.ps1    # Refactor metric computation → Get-AssessmentMetrics
```

### Output

```
Assessment_YYYYMMDD_HHMMSS/
├─ _Assessment-Report.html           # Existing
├─ _Assessment-Deck.pptx             # NEW
├─ _Assessment-Summary.csv           # Existing
├─ _Assessment-Issues.log            # Existing
└─ *.csv                             # Existing collector outputs
```

---

## 10. Risk & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **OpenXML SDK size** (~5MB) | Increases repo/download size | Ship as separate optional download; or use NuGet install on first run |
| **Chart generation complexity** | OpenXML chart API is verbose and poorly documented | Start with text-only MVP (Phase 1), add charts incrementally. Use reference .pptx files to reverse-engineer XML structure |
| **Cross-platform rendering** | Chart appearance may vary | Use native PresentationML charts — rendering is handled by PowerPoint/LibreOffice at view time |
| **Template maintenance** | Template changes must stay in sync with code | Template uses named placeholders with a strict convention; validation function checks all expected placeholders exist |
| **Metric logic duplication** | HTML and PPTX reports diverge | Extract shared `Get-AssessmentMetrics.ps1` in Phase 1 to ensure single source of truth |
| **Large assessment data** | 328-row MFA table won't fit on a slide | Deck is executive-focused: show aggregates (MFA adoption %), not row-level data. Link to HTML report for details |

---

## 11. Future Enhancements

- **Customizable slide selection** — Let consultants choose which slides to include via a parameter (e.g., `-DeckSections Identity,Email,Remediation`)
- **Multi-language support** — Slide text templates in JSON for localization
- **Comparison decks** — Side-by-side comparison with a previous assessment (trend arrows, delta values)
- **Speaker notes AI** — Use assessment context to generate presenter talking points per slide
- **Teams integration** — Auto-upload deck to a Teams channel or SharePoint site after generation
- **Branded template gallery** — Ship multiple template styles (corporate, modern, minimal) selectable via `-DeckTheme`
