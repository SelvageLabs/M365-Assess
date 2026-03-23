# Architecture Diagrams

Mermaid diagrams documenting M365-Assess core functionality and integrations. These render natively on GitHub -- no plugins required.

## Diagrams

| Diagram | Description |
|---------|-------------|
| [Core Pipeline](core-pipeline.md) | End-to-end 5-phase assessment flow: initialization, service connections, collector execution, deferred DNS, and report generation |
| [Upstream Integrations](upstream-integrations.md) | All external systems (CheckID, Graph API, EXO, Purview, DNS, PSGallery, MITRE) and output formats (HTML, XLSX, CSV) |
| [CheckId Data Flow](checkid-data-flow.md) | Sequence diagram tracing a CheckId from the CheckID repo through CI sync, collector execution, and report enrichment |
| [Service Connections](service-connections.md) | Connection architecture showing lazy connections, EXO/Purview mutual exclusion, PowerBI process isolation, and DNS prefetch |

## Viewing

These diagrams use [Mermaid](https://mermaid.js.org/) syntax in fenced code blocks. They render automatically on:

- **GitHub** -- native support in Markdown files
- **VS Code** -- with the [Markdown Preview Mermaid Support](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid) extension
- **Mermaid Live Editor** -- paste diagram code at [mermaid.live](https://mermaid.live)
