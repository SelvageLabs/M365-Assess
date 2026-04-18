function Get-ReportTemplate {
    <#
    .SYNOPSIS
        Produces a self-contained HTML report document from REPORT_DATA JSON.
    .DESCRIPTION
        Inlines the React 18 production build, compiled report-app.js, CSS theme files,
        and window.REPORT_DATA JSON into a single HTML file with no external dependencies.
        The file is fully offline-capable and can be opened without a web server.
    .PARAMETER ReportDataJson
        The full window.REPORT_DATA = {...}; assignment string produced by Build-ReportDataJson.
    .PARAMETER ReportTitle
        Text for the HTML <title> element. Defaults to 'M365 Security Assessment'.
    .EXAMPLE
        $json = Build-ReportDataJson -AllFindings $findings -SectionData $sectionData -RegistryData $registry
        $html = Get-ReportTemplate -ReportDataJson $json -ReportTitle 'Contoso Assessment'
        Set-Content -Path .\report.html -Value $html -Encoding UTF8
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ReportDataJson,

        [Parameter()]
        [string]$ReportTitle = 'M365 Security Assessment'
    )

    $assetsDir = Join-Path -Path $PSScriptRoot -ChildPath '../assets'

    $themesCss  = Get-Content -Path (Join-Path $assetsDir 'report-themes.css')             -Raw -ErrorAction Stop
    $shellCss   = Get-Content -Path (Join-Path $assetsDir 'report-shell.css')              -Raw -ErrorAction Stop
    $reactJs    = Get-Content -Path (Join-Path $assetsDir 'react.production.min.js')       -Raw -ErrorAction Stop
    $reactDomJs = Get-Content -Path (Join-Path $assetsDir 'react-dom.production.min.js')   -Raw -ErrorAction Stop
    $appJs      = Get-Content -Path (Join-Path $assetsDir 'report-app.js')                 -Raw -ErrorAction Stop

    # Use StringBuilder so JS/CSS content is appended as .NET strings — never PS-interpolated
    $sb = [System.Text.StringBuilder]::new(2097152) # 2 MB initial capacity

    $null = $sb.AppendLine('<!DOCTYPE html>')
    $null = $sb.AppendLine('<html data-theme="dark" data-mode="comfort">')
    $null = $sb.AppendLine('<head>')
    $null = $sb.AppendLine('<meta charset="UTF-8">')
    $null = $sb.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1.0">')
    $null = $sb.AppendLine("<title>$([System.Web.HttpUtility]::HtmlEncode($ReportTitle))</title>")
    $null = $sb.AppendLine('<style>')
    $null = $sb.Append($themesCss)
    $null = $sb.AppendLine()
    $null = $sb.Append($shellCss)
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('</style>')
    $null = $sb.AppendLine('</head>')
    $null = $sb.AppendLine('<body>')
    $null = $sb.AppendLine('<div id="app-root"></div>')
    $null = $sb.AppendLine('<script>')
    $null = $sb.Append($ReportDataJson)
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('</script>')
    $null = $sb.AppendLine('<script>')
    $null = $sb.Append($reactJs)
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('</script>')
    $null = $sb.AppendLine('<script>')
    $null = $sb.Append($reactDomJs)
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('</script>')
    $null = $sb.AppendLine('<script>')
    $null = $sb.Append($appJs)
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('</script>')
    $null = $sb.AppendLine('</body>')
    $null = $sb.Append('</html>')

    return $sb.ToString()
}
