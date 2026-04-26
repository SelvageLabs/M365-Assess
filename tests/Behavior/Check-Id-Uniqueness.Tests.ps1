BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:registryPath = Join-Path $repoRoot 'src/M365-Assess/controls/registry.json'
    $script:registry = Get-Content $script:registryPath -Raw | ConvertFrom-Json
    # Registry shape: { schemaVersion, dataVersion, generatedFrom, checks: [ { checkId, ... }, ... ] }
    $script:checkIds = if ($script:registry.PSObject.Properties.Name -contains 'checks') {
        @($script:registry.checks | ForEach-Object { $_.checkId })
    } else {
        # Fallback: legacy registry.json shape with check IDs as top-level property names
        $script:registry.PSObject.Properties.Name
    }
}

Describe 'Check ID uniqueness in registry (C5 #784)' {

    It 'should load the registry without parse errors' {
        $script:registry | Should -Not -BeNullOrEmpty
        $script:checkIds.Count | Should -BeGreaterThan 0
    }

    It 'should not contain duplicate base CheckIds' {
        $duplicates = $script:checkIds | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name

        if ($duplicates.Count -gt 0) {
            throw "Registry contains $($duplicates.Count) duplicate CheckId(s):`n$($duplicates -join ', ')"
        }
    }

    It 'should follow the documented CheckId naming convention' {
        # Pattern: uppercase letters/digits/hyphens, starting with a letter, multi-segment.
        # Real CheckIds range from 2 segments (DNS-MX-001) to 4+ (DEFENDER-PRESET-ZAP-001).
        $validPattern = '^[A-Z][A-Z0-9]*(-[A-Z0-9]+)+$'
        $bad = $script:checkIds | Where-Object { $_ -notmatch $validPattern }

        if ($bad.Count -gt 0) {
            throw "Registry contains $($bad.Count) CheckId(s) violating naming convention:`n$(($bad | Select-Object -First 10) -join ', ')$(if ($bad.Count -gt 10) { "  (and $($bad.Count - 10) more)" })"
        }
    }
}
