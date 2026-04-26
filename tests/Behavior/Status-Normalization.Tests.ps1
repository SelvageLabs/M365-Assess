BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/M365-Assess/Common/SecurityConfigHelper.ps1')

    # Authoritative status values from the Add-SecuritySetting ValidateSet (B3 #774).
    # Update this list if the helper's enum changes.
    $script:validStatuses = @('Pass', 'Fail', 'Warning', 'Review', 'Info', 'Skipped', 'Unknown', 'NotApplicable', 'NotLicensed')
}

Describe 'Status normalization across collectors (C5 #784)' {

    Context 'SecurityConfigHelper enforces the canonical taxonomy' {
        It 'should accept every documented status value' {
            $ctx = Initialize-SecurityConfig
            foreach ($status in $script:validStatuses) {
                {
                    Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
                        -Category 'Test' -Setting "test for $status" -CurrentValue 'x' `
                        -RecommendedValue 'y' -Status $status -CheckId 'TEST-001'
                } | Should -Not -Throw
            }
        }

        It 'should reject statuses outside the taxonomy' {
            $ctx = Initialize-SecurityConfig
            {
                Add-SecuritySetting -Settings $ctx.Settings -CheckIdCounter $ctx.CheckIdCounter `
                    -Category 'Test' -Setting 'invalid' -CurrentValue 'x' `
                    -RecommendedValue 'y' -Status 'BogusStatus' -CheckId 'TEST-001'
            } | Should -Throw
        }
    }

    Context 'static check: security-finding collectors do not emit unknown statuses' {
        It 'should not contain non-canonical Status literals near Add-Setting calls' {
            # Scope: only files that actually emit security findings via Add-Setting.
            # AD inventory collectors (Get-ADReplicationReport, etc.) use their own
            # 'Status' field on PSCustomObject state records (e.g. 'QueryFailed',
            # 'Configured') -- those are state-tracking, not the assessment Status
            # taxonomy. Narrow the check to files that call Add-Setting / Add-SecuritySetting.
            $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
            $collectorRoots = @('Entra', 'Security', 'Exchange-Online', 'Purview', 'Intune', 'PowerBI', 'Collaboration') |
                ForEach-Object { Join-Path $repoRoot ('src/M365-Assess/' + $_) }

            $bogusFound = [System.Collections.Generic.List[string]]::new()
            foreach ($root in $collectorRoots) {
                if (-not (Test-Path $root)) { continue }
                $files = Get-ChildItem $root -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue
                foreach ($f in $files) {
                    $content = Get-Content $f.FullName -Raw
                    # Skip files that don't emit security findings
                    if ($content -notmatch '\bAdd-(?:Security)?Setting\b') { continue }
                    # Match Status assignments: Status = 'Whatever' or Status = "Whatever"
                    $regexMatches = [regex]::Matches($content, "Status\s*=\s*['""]([A-Za-z]+)['""]")
                    foreach ($m in $regexMatches) {
                        $value = $m.Groups[1].Value
                        if ($value -notin $script:validStatuses) {
                            $bogusFound.Add("$($f.FullName): Status = '$value'")
                        }
                    }
                }
            }

            if ($bogusFound.Count -gt 0) {
                throw "Found $($bogusFound.Count) collector(s) emitting non-canonical Status literal(s):`n$(($bogusFound | Sort-Object -Unique) -join [Environment]::NewLine)"
            }
        }
    }
}
