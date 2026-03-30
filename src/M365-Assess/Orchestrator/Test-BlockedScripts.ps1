function Test-BlockedScripts {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [switch]$NonInteractive
    )

if ($IsWindows -or $null -eq $IsWindows) {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -eq 'Undefined') { $policy = Get-ExecutionPolicy -Scope LocalMachine }
    $blockedFiles = @(Get-ChildItem -Path $projectRoot -Recurse -Filter '*.ps1' |
        Where-Object { (Get-Item -Path $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) })

    if ($blockedFiles.Count -gt 0 -and $policy -notin @('Bypass', 'Unrestricted')) {
        Write-Host ''
        Write-Host '  ╔══════════════════════════════════════════════════════════╗' -ForegroundColor Yellow
        Write-Host '  ║  Blocked Scripts Detected                               ║' -ForegroundColor Yellow
        Write-Host '  ╚══════════════════════════════════════════════════════════╝' -ForegroundColor Yellow
        Write-Host "    $($blockedFiles.Count) .ps1 file(s) are marked as downloaded from the internet." -ForegroundColor Yellow
        Write-Host "    ExecutionPolicy '$policy' will block them when they are loaded." -ForegroundColor Yellow
        Write-Host ''

        if ($NonInteractive -or -not [Environment]::UserInteractive) {
            Write-Host '    Run this to unblock:' -ForegroundColor Red
            Write-Host "    Get-ChildItem -Path '$projectRoot' -Recurse -Filter '*.ps1' | Unblock-File" -ForegroundColor Red
            Write-Host ''
            Write-Error "Blocked scripts detected. Unblock files and try again."
            return
        }

        $response = Read-Host '  Remove internet zone marks (Unblock-File) for this project? [Y/n]'
        if ($response -match '^[Yy]?$') {
            try {
                $blockedFiles | Unblock-File -ErrorAction Stop
                Write-Host "    ✓ $($blockedFiles.Count) file(s) unblocked" -ForegroundColor Green
            }
            catch {
                Write-Host "    ✗ Unblock failed: $_" -ForegroundColor Red
                Write-Host "    Try running PowerShell as Administrator, or run manually:" -ForegroundColor Yellow
                Write-Host "    Get-ChildItem -Path '$projectRoot' -Recurse -Filter '*.ps1' | Unblock-File" -ForegroundColor Yellow
                Write-Error "Cannot unblock scripts. See above for manual steps."
                return
            }
        }
        else {
            Write-Error "Blocked scripts cannot be loaded. Unblock files and try again."
            return
        }
        Write-Host ''
    }
}

    return $true
}
