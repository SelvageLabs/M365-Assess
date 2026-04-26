BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/M365-Assess/Common/Get-RedactionRules.ps1')
    . (Join-Path $PSScriptRoot '../../src/M365-Assess/Common/Export-EvidencePackage.ps1')
}

Describe 'Export-EvidencePackage (D4 #788)' {

    BeforeEach {
        # Build a minimal fake assessment folder.
        $script:assessFolder = Join-Path -Path $TestDrive -ChildPath 'Assessment_test'
        New-Item -Path $script:assessFolder -ItemType Directory -Force | Out-Null

        # Summary CSV (the only file Export-EvidencePackage requires; everything else is best-effort)
        @(
            [PSCustomObject]@{ Collector = 'EXO'; FileName = 'exo-config.csv'; Items = 1; Status = 'Complete' }
        ) | Export-Csv -Path (Join-Path $script:assessFolder '_Assessment-Summary.csv') -NoTypeInformation -Encoding UTF8

        # Per-collector CSV with structured evidence
        @(
            [PSCustomObject]@{
                CheckId            = 'EXO-AUTH-001.1'
                Setting            = 'Modern Authentication Enabled'
                Status             = 'Pass'
                Category           = 'Authentication'
                CurrentValue       = 'True'
                RecommendedValue   = 'True'
                Remediation        = ''
                ObservedValue      = 'True'
                ExpectedValue      = 'True'
                EvidenceSource     = 'Get-OrganizationConfig'
                EvidenceTimestamp  = ''
                CollectionMethod   = 'Direct'
                PermissionRequired = 'Exchange Online: View-Only Configuration'
                Confidence         = '1.0'
                Limitations        = ''
            }
        ) | Export-Csv -Path (Join-Path $script:assessFolder 'exo-config.csv') -NoTypeInformation -Encoding UTF8

        # Stub HTML + XLSX so the package picks them up
        Set-Content -Path (Join-Path $script:assessFolder 'fake_Assessment-Report.html') -Value '<html><body>stub</body></html>'
        Set-Content -Path (Join-Path $script:assessFolder 'fake_Compliance-Matrix.xlsx')  -Value 'stub-bytes'
    }

    It 'writes a ZIP at the expected location' {
        $out = Join-Path $TestDrive 'package.zip'
        $result = Export-EvidencePackage -AssessmentFolder $script:assessFolder -OutputPath $out -TenantName 'test'
        $result | Should -Be $out
        Test-Path $out | Should -BeTrue
    }

    It 'includes the seven documented files plus a manifest' {
        $out = Join-Path $TestDrive 'package.zip'
        Export-EvidencePackage -AssessmentFolder $script:assessFolder -OutputPath $out -TenantName 'test' | Out-Null

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($out)
        try {
            $names = @($zip.Entries | ForEach-Object { $_.FullName })
        } finally { $zip.Dispose() }

        $names | Should -Contain 'manifest.json'
        $names | Should -Contain 'executive-report.html'
        $names | Should -Contain 'compliance-matrix.xlsx'
        $names | Should -Contain 'findings.json'
        $names | Should -Contain 'permissions-summary.json'
        $names | Should -Contain 'run-metadata.json'
        $names | Should -Contain 'known-limitations.md'
        $names | Should -Contain 'README.md'
    }

    It 'manifest SHA-256 hashes match the file contents in the ZIP' {
        $out = Join-Path $TestDrive 'package.zip'
        Export-EvidencePackage -AssessmentFolder $script:assessFolder -OutputPath $out -TenantName 'test' | Out-Null

        $extract = Join-Path $TestDrive 'extract'
        if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
        New-Item -Path $extract -ItemType Directory -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($out, $extract)

        $manifest = Get-Content (Join-Path $extract 'manifest.json') -Raw | ConvertFrom-Json
        foreach ($entry in $manifest.files) {
            $actual = (Get-FileHash -Path (Join-Path $extract $entry.path) -Algorithm SHA256).Hash.ToLower()
            $actual | Should -Be $entry.sha256
        }
    }

    It 'redaction strips UPNs from findings.json when -Redact is supplied' {
        # Add a finding with a UPN
        @(
            [PSCustomObject]@{
                CheckId            = 'TEST-001.1'
                Setting            = 'admin@contoso.com is global admin'
                Status             = 'Warning'
                Category           = 'Auth'
                CurrentValue       = 'admin@contoso.com'
                RecommendedValue   = 'least-privilege'
                Remediation        = ''
                ObservedValue      = ''
                ExpectedValue      = ''
                EvidenceSource     = ''
                EvidenceTimestamp  = ''
                CollectionMethod   = ''
                PermissionRequired = ''
                Confidence         = ''
                Limitations        = ''
            }
        ) | Export-Csv -Path (Join-Path $script:assessFolder 'admin-config.csv') -NoTypeInformation -Encoding UTF8

        $out = Join-Path $TestDrive 'package-redacted.zip'
        Export-EvidencePackage -AssessmentFolder $script:assessFolder -OutputPath $out -TenantName 'test' -Redact -TenantDisplayName 'Contoso' | Out-Null

        $extract = Join-Path $TestDrive 'extract-redacted'
        if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($out, $extract)

        $findings = Get-Content (Join-Path $extract 'findings.json') -Raw
        $findings | Should -Not -Match 'admin@contoso\.com'
        $findings | Should -Match '<user-[0-9a-f]{8}>'
    }

    It 'records redactionApplied=true in run-metadata.json when -Redact is supplied' {
        $out = Join-Path $TestDrive 'package-meta.zip'
        Export-EvidencePackage -AssessmentFolder $script:assessFolder -OutputPath $out -TenantName 'test' -Redact | Out-Null

        $extract = Join-Path $TestDrive 'extract-meta'
        if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($out, $extract)

        $meta = Get-Content (Join-Path $extract 'run-metadata.json') -Raw | ConvertFrom-Json
        $meta.redactionApplied | Should -BeTrue
        $meta.tenantName       | Should -Be '<tenant>'
    }

    It 'rejects a non-existent assessment folder with a clear error' {
        { Export-EvidencePackage -AssessmentFolder 'C:\does\not\exist' -OutputPath (Join-Path $TestDrive 'x.zip') } |
            Should -Throw '*not found*'
    }
}
