---
paths:
  - "**/*.ps1"
  - "**/*.psm1"
  - "**/*.psd1"
---

# PowerShell Script Rules

## File Organization
- Scripts organized by domain folder (ActiveDirectory, Entra, Exchange-Online, Intune, Purview, Windows, Networking, Security)
- Shared helpers go in `Common/`
- Scripts run as part of the M365-Assess PSGallery module — collectors dot-source
  `Common/SecurityConfigHelper.ps1` for the `Add-Setting` contract and use
  `Invoke-MgGraphRequest` from the loaded Microsoft.Graph SDK
- Script names use `Verb-Noun.ps1` convention (e.g., `Get-LicenseReport.ps1`)

## Required Script Structure

Every script MUST include:

```powershell
<#
.SYNOPSIS
    Brief description.
.DESCRIPTION
    Detailed description.
.PARAMETER ParameterName
    Parameter description.
.EXAMPLE
    PS> .\FolderName\Verb-Noun.ps1 -ParameterName 'Value'
    Example description showing realistic IT consultant usage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ParameterName
)

# Script body
```

For scripts that define a reusable function (especially in Common/):

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description.
    .DESCRIPTION
        Detailed description.
    .PARAMETER ParameterName
        Parameter description.
    .EXAMPLE
        Verb-Noun -ParameterName 'Value'
    #>
    [CmdletBinding()]
    [OutputType([TypeName])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterName
    )

    # Function body
}
```

## Forbidden Patterns
- No aliases — always use full cmdlet names (`Get-ChildItem` not `gci`, `ForEach-Object` not `%`)
- No `Write-Host` for data output — use `Write-Output` (Write-Host is OK for console status messages)
- No backtick (`` ` ``) line continuations — use splatting or natural line breaks
- No `$global:` scope
- No positional parameters — always use `-ParameterName Value` syntax
- No `Invoke-Expression` — security risk, always find a safer alternative

## Execution
- Always run PowerShell commands via: `pwsh -NoProfile -Command "..."`
- Lint with: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path '.' -Recurse -Severity Warning -ExcludePath '.claude'"`
