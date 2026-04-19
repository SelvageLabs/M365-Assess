# HTML Assessment Report

The assessment generates a self-contained HTML report (`_Assessment-Report.html`) that can be emailed directly to clients. No external dependencies, no assets folder needed. All logos are base64-encoded, styles and scripts are embedded inline.

## Report Features

The v2 report is a React 18 single-file HTML application — no server, no assets folder, no external dependencies. All styles, scripts, and data are embedded inline.

- **Multiple themes** — Default, Neon, Blueprint, Slate, and High Contrast, each with light and dark variants. Auto-detection via `prefers-color-scheme`, `localStorage` persistence, and WCAG AAA support in high-contrast mode.
- **Posture hero** with tenant name, organization profile card (org name, primary domain, creation date, security defaults status), and live security posture KPIs
- **Identity KPIs** — total users, licensed users, MFA adoption %, SSPR enrollment %, guest count (MFA/SSPR denominators exclude non-capable accounts)
- **Microsoft Secure Score** — stat card, progress bar with peer-average comparison, and a real Secure Score history sparkline (up to 180 days from Graph, dynamically labeled)
- **Domain donut charts** — Pass/Fail/Warning/Review/Info breakdown for each domain (Entra, EXO, Defender, SharePoint, Teams)
- **Findings table** — sortable, searchable, filterable by status, severity, domain, and framework; severity and framework badges inline
- **Compliance Overview** — interactive framework selector, coverage cards, CIS E3/E5 sub-filters, and cross-reference matrix (see [COMPLIANCE.md](COMPLIANCE.md))
- **Remediation Action Plan** — prioritized list of actionable fixes with effort estimates and impact metadata
- **Appendix** — full section-by-section data tables with sortable headers, status/severity chip filters, column picker, and CSV export
- **Color-coded status badges** (Pass/Fail/Warning/Review/Info) with row-level tinting on security config tables
- **Accessibility** — semantic HTML landmarks, `scope="col"` on table headers, focus-visible outlines
- **Print-friendly** — `window.print()` with optimized print CSS; no external PDF generator required

## Standalone Report Generation

Re-generate the HTML report from existing CSV data without re-running the full assessment:

```powershell
.\Common\Export-AssessmentReport.ps1 -AssessmentFolder '.\M365-Assessment\Assessment_YYYYMMDD_HHMMSS'
```

This is useful for:
- Regenerating the report after a branding change
- Testing report layout changes against existing data
- Generating reports from CSV data collected on another system

## White Label

Use `-WhiteLabel` to generate a report without the M365 Assess GitHub link and Galvnyz attribution in the footer:

```powershell
Invoke-M365Assessment -TenantId 'contoso.onmicrosoft.com' -WhiteLabel
```

This produces a clean report with your tenant name and data but no open-source attribution. Ideal for client delivery.
