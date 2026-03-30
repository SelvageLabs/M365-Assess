BeforeDiscovery {
    $repoRoot = Resolve-Path "$PSScriptRoot/../.."
    $manifestPath = Join-Path $repoRoot 'src/M365-Assess/M365-Assess.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
}

Describe 'PSGallery Readiness' {
    BeforeAll {
        $repoRoot = Resolve-Path "$PSScriptRoot/../.."
        $moduleRoot = Join-Path $repoRoot 'src/M365-Assess'
        $manifestPath = Join-Path $moduleRoot 'M365-Assess.psd1'
        $manifest = Import-PowerShellDataFile -Path $manifestPath
    }

    Context 'Module manifest' {
        It 'Test-ModuleManifest passes without errors' {
            { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Has a Description' {
            $manifest.Description | Should -Not -BeNullOrEmpty
        }

        It 'Has an Author' {
            $manifest.Author | Should -Not -BeNullOrEmpty
        }

        It 'Has a GUID' {
            $manifest.GUID | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid ModuleVersion' {
            $manifest.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
        }

        It 'Has a LicenseUri' {
            $manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
        }

        It 'Has a ProjectUri' {
            $manifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
        }

        It 'Has Tags for PSGallery discoverability' {
            $manifest.PrivateData.PSData.Tags | Should -Not -BeNullOrEmpty
            $manifest.PrivateData.PSData.Tags.Count | Should -BeGreaterThan 5
        }

        It 'RootModule points to .psm1 file' {
            $manifest.RootModule | Should -BeLike '*.psm1'
        }

        It 'RootModule file exists' {
            $rootModulePath = Join-Path $moduleRoot $manifest.RootModule
            $rootModulePath | Should -Exist
        }

        It 'FunctionsToExport is explicitly set (not wildcard)' {
            $manifest.FunctionsToExport | Should -Not -Be '*'
            $manifest.FunctionsToExport | Should -Contain 'Invoke-M365Assessment'
        }

        It 'CmdletsToExport is explicitly empty' {
            $manifest.CmdletsToExport | Should -HaveCount 0
        }

        It 'Has ReleaseNotes' {
            $manifest.PrivateData.PSData.ReleaseNotes | Should -Not -BeNullOrEmpty
        }
    }

    Context 'FileList integrity' {
        It 'Every file in FileList exists on disk' {
            $missing = @()
            foreach ($file in $manifest.FileList) {
                $fullPath = Join-Path $moduleRoot $file
                if (-not (Test-Path $fullPath)) {
                    $missing += $file
                }
            }
            $missing | Should -HaveCount 0 -Because "these files are listed in manifest but missing: $($missing -join ', ')"
        }
    }

    Context 'Module loading' {
        It 'Import-Module succeeds without errors' {
            { Import-Module $manifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Get-Command returns Invoke-M365Assessment' {
            Import-Module $manifestPath -Force
            $commands = Get-Command -Module M365-Assess
            $commands.Name | Should -Contain 'Invoke-M365Assessment'
        }
    }

    Context 'Package hygiene' {
        It 'LICENSE file exists' {
            Join-Path $repoRoot 'LICENSE' | Should -Exist
        }

        It 'README.md exists' {
            Join-Path $repoRoot 'README.md' | Should -Exist
        }

        It 'No .env files in repo root' {
            Join-Path $repoRoot '.env' | Should -Not -Exist
        }

        It 'No credential files in repo root' {
            Join-Path $repoRoot 'credentials.json' | Should -Not -Exist
        }

        It 'No ScubaGear tool references remain in manifest' {
            $manifest.Description | Should -Not -Match 'ScubaGear'
            $manifest.PrivateData.PSData.Tags | Should -Not -Contain 'ScubaGear'
            $manifest.FileList | Should -Not -Contain 'Security\Invoke-ScubaGearScan.ps1'
        }
    }
}
