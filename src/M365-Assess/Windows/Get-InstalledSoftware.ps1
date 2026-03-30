<#
.SYNOPSIS
    Inventories installed software from the Windows registry.
.DESCRIPTION
    Reads the Uninstall registry keys to enumerate installed software on local
    or remote computers. More reliable than Win32_Product (which triggers MSI
    reconfiguration). Checks both 64-bit and 32-bit registry hives.

    No external modules required. Uses remote registry or CIM for remote queries.
.PARAMETER ComputerName
    One or more computer names to query. Defaults to the local computer.
    Accepts pipeline input.
.PARAMETER Credential
    Credential for remote computer access. Not needed for the local computer.
.PARAMETER OutputPath
    Optional path to export results as CSV.
.EXAMPLE
    PS> .\Windows\Get-InstalledSoftware.ps1

    Lists all installed software on the local computer.
.EXAMPLE
    PS> .\Windows\Get-InstalledSoftware.ps1 -ComputerName 'SERVER01','SERVER02'

    Lists installed software on multiple remote computers.
.EXAMPLE
    PS> Get-Content .\servers.txt | .\Windows\Get-InstalledSoftware.ps1 -OutputPath '.\software-inventory.csv'

    Reads server names from a file and exports a full software inventory to CSV.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('CN')]
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$OutputPath
)

begin {
    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
}

process {
    foreach ($computer in $ComputerName) {
        Write-Verbose "Querying installed software on $computer"

        try {
            if ($computer -eq $env:COMPUTERNAME -and -not $Credential) {
                # Local computer - read registry directly
                foreach ($path in $registryPaths) {
                    $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' }

                    foreach ($item in $items) {
                        $allResults.Add([PSCustomObject]@{
                            ComputerName    = $computer
                            DisplayName     = $item.DisplayName
                            DisplayVersion  = $item.DisplayVersion
                            Publisher        = $item.Publisher
                            InstallDate     = $item.InstallDate
                            InstallLocation = $item.InstallLocation
                            UninstallString = $item.UninstallString
                            Architecture    = if ($path -match 'WOW6432Node') { '32-bit' } else { '64-bit' }
                        })
                    }
                }
            }
            else {
                # Remote computer - use Invoke-Command
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = {
                        $paths = @(
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                        )
                        foreach ($path in $paths) {
                            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' }

                            foreach ($item in $items) {
                                [PSCustomObject]@{
                                    DisplayName     = $item.DisplayName
                                    DisplayVersion  = $item.DisplayVersion
                                    Publisher        = $item.Publisher
                                    InstallDate     = $item.InstallDate
                                    InstallLocation = $item.InstallLocation
                                    UninstallString = $item.UninstallString
                                    Architecture    = if ($path -match 'WOW6432Node') { '32-bit' } else { '64-bit' }
                                }
                            }
                        }
                    }
                    ErrorAction = 'Stop'
                }
                if ($Credential) {
                    $invokeParams['Credential'] = $Credential
                }

                $remoteResults = Invoke-Command @invokeParams

                foreach ($item in $remoteResults) {
                    $allResults.Add([PSCustomObject]@{
                        ComputerName    = $computer
                        DisplayName     = $item.DisplayName
                        DisplayVersion  = $item.DisplayVersion
                        Publisher        = $item.Publisher
                        InstallDate     = $item.InstallDate
                        InstallLocation = $item.InstallLocation
                        UninstallString = $item.UninstallString
                        Architecture    = $item.Architecture
                    })
                }
            }

            Write-Verbose "${computer}: Found $($allResults.Count) software entries"
        }
        catch {
            Write-Warning "Failed to query $computer`: $_"
            $allResults.Add([PSCustomObject]@{
                ComputerName    = $computer
                DisplayName     = "ERROR: $_"
                DisplayVersion  = $null
                Publisher        = $null
                InstallDate     = $null
                InstallLocation = $null
                UninstallString = $null
                Architecture    = $null
            })
        }
    }
}

end {
    $allResults = @($allResults) | Sort-Object -Property ComputerName, DisplayName

    if ($OutputPath) {
        $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported $($allResults.Count) software entries to $OutputPath"
    }
    else {
        Write-Output $allResults
    }
}
