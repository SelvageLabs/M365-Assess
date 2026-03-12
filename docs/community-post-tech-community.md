# I built a free, open-source M365 security assessment tool for IT consultants and admins -- looking for feedback

> **Post target:** Microsoft Tech Community Blog
> **Tone:** Practitioner sharing work, inviting community feedback
> **Screenshots needed:** 4 (see placeholders below)

---

I work as an IT consultant, and a good chunk of my time is spent assessing Microsoft 365 environments for small and mid-sized businesses. Every engagement started the same way: connect to five different PowerShell modules, run dozens of commands across Entra ID, Exchange Online, Defender, SharePoint, and Teams, manually compare each setting against CIS benchmarks, then spend hours assembling everything into a report the client could actually read.

The tools that automate this either cost thousands per year, require standing up Azure infrastructure just to run, or only cover one service area. I wanted something simpler: one command that connects, assesses, and produces a client-ready deliverable. So I built it.

## What M365 Assess does

[M365 Assess](https://github.com/Daren9m/M365-Assess) is a PowerShell-based security assessment tool that runs against a Microsoft 365 tenant and produces a comprehensive set of reports. Here is what you get from a single run:

- **57 automated security checks** aligned to the CIS Microsoft 365 Foundations Benchmark v6.0.1, covering Entra ID, Exchange Online, Defender for Office 365, SharePoint Online, and Teams
- **12 compliance frameworks mapped simultaneously** -- every finding is cross-referenced against NIST 800-53, NIST CSF 2.0, ISO 27001:2022, SOC 2, HIPAA, PCI DSS v4.0.1, CMMC 2.0, CISA SCuBA, and DISA STIG (plus CIS profiles for E3 L1/L2 and E5 L1/L2)
- **20+ CSV exports** covering users, mailboxes, MFA status, admin roles, conditional access policies, mail flow rules, device compliance, and more
- **A self-contained HTML report** with an executive summary, severity badges, sortable tables, and a compliance overview dashboard -- no external dependencies, fully base64-encoded, just open it in any browser or email it directly

The entire assessment is **read-only**. It never modifies tenant settings. Only `Get-*` cmdlets are used.

## A few things I'm proud of

**Real-time progress in the console.** As the assessment runs, you see each check complete with live status indicators and timing. No staring at a blank terminal wondering if it hung.

<!-- SCREENSHOT 1: Console progress display during assessment run -->
`[Insert screenshot: Console with real-time progress display]`

**The HTML report is a single file.** Logos, backgrounds, fonts -- everything is embedded. You can email the report as an attachment and it renders perfectly. It supports dark mode (auto-detects system preference), and all tables are sortable by clicking column headers.

<!-- SCREENSHOT 2: Report executive summary / cover page -->
`[Insert screenshot: HTML report cover page with executive summary]`

**Compliance framework mapping.** This was the feature that took the most work. The compliance overview shows coverage percentages across all 12 frameworks, with drill-down to individual controls. Each finding links back to its CIS control ID and maps to every applicable framework control.

<!-- SCREENSHOT 3: Compliance overview with framework cards -->
`[Insert screenshot: Compliance overview dashboard with framework coverage cards]`

**Pass/Fail detail tables.** Each security check shows the CIS control reference, what was checked, what the expected value is, what the actual value is, and a clear Pass/Fail/Warning status. Findings include remediation descriptions to help prioritize fixes.

<!-- SCREENSHOT 4: Detail table showing Pass/Fail rows -->
`[Insert screenshot: Security configuration detail table with status badges]`

## Quick start

If you want to try it out, it takes about 5 minutes to get running:

```powershell
# Install prerequisites (if you don't have them already)
Install-Module Microsoft.Graph, ExchangeOnlineManagement -Scope CurrentUser

# Clone and run
git clone https://github.com/Daren9m/M365-Assess.git
cd M365-Assess
.\Invoke-M365Assessment.ps1
```

The interactive wizard walks you through selecting assessment sections, entering your tenant ID, and choosing an authentication method (interactive browser login, certificate-based, or pre-existing connections). Results land in a timestamped folder with all CSVs and the HTML report.

Requires **PowerShell 7.x** and runs on Windows (macOS and Linux are experimental -- I would love help testing those platforms).

## Cloud support

M365 Assess works with:

- Commercial (global) tenants
- GCC, GCC High, and DoD environments

If you work in government cloud, the tool handles the different endpoint URIs automatically.

## What is next

This is actively maintained and I have a roadmap of improvements:

- **More automated checks** -- 140 CIS v6.0.1 controls are tracked in the registry, with 57 automated today. Expanding coverage is the top priority.
- **Remediation commands** -- PowerShell snippets and portal steps for each finding, so you can fix issues directly from the report.
- **XLSX compliance matrix** -- A spreadsheet export for audit teams who need to work in Excel.
- **Standalone report regeneration** -- Re-run the report from existing CSV data without re-assessing the tenant.

## I would love your feedback

I have been building this for my own consulting work, but I think it could be useful to the broader community. If you try it, I would genuinely appreciate hearing:

- **What checks should I prioritize next?** Which CIS controls matter most in your environment?
- **What compliance frameworks are most requested** by your clients or auditors?
- **How does the report land with non-technical stakeholders?** Is the executive summary useful, or does it need work?
- **macOS/Linux users** -- does it run? What breaks?

Bug reports, feature requests, and contributions are all welcome on GitHub.

**Repository:** [https://github.com/Daren9m/M365-Assess](https://github.com/Daren9m/M365-Assess)
**License:** MIT (free for commercial and personal use)
**Runtime:** PowerShell 7.x

Thanks for reading. Happy to answer any questions in the comments.
