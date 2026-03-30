<#
.SYNOPSIS
    Tests TCP port connectivity to one or more hosts.
.DESCRIPTION
    Attempts TCP connections to specified ports on target hosts and reports
    whether each port is open or closed. Useful for firewall validation,
    migration readiness checks, and network troubleshooting. Uses
    System.Net.Sockets.TcpClient for fast, lightweight connection tests.

    No external modules required.
.PARAMETER ComputerName
    One or more hostnames or IP addresses to test. Accepts pipeline input.
.PARAMETER Port
    One or more TCP ports to test on each host.
.PARAMETER Timeout
    Connection timeout in milliseconds. Defaults to 1000 (1 second).
.PARAMETER OutputPath
    Optional path to export results as CSV.
.EXAMPLE
    PS> .\Networking\Test-PortConnectivity.ps1 -ComputerName 'server01' -Port 443,80,3389

    Tests ports 443, 80, and 3389 on server01.
.EXAMPLE
    PS> .\Networking\Test-PortConnectivity.ps1 -ComputerName 'dc01','dc02' -Port 389,636,53 -Timeout 2000

    Tests LDAP, LDAPS, and DNS ports on two domain controllers with a 2-second timeout.
.EXAMPLE
    PS> Get-Content .\servers.txt | .\Networking\Test-PortConnectivity.ps1 -Port 443 -OutputPath '.\port-scan.csv'

    Reads server names from a file and exports port 443 connectivity results to CSV.
.EXAMPLE
    PS> .\Networking\Test-PortConnectivity.ps1 -ComputerName '10.0.0.1' -Port 22,3389,5985

    Tests SSH, RDP, and WinRM ports on a specific IP address.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('CN', 'HostName', 'IPAddress')]
    [string[]]$ComputerName,

    [Parameter(Mandatory)]
    [ValidateRange(1, 65535)]
    [int[]]$Port,

    [Parameter()]
    [ValidateRange(100, 30000)]
    [int]$Timeout = 1000,

    [Parameter()]
    [string]$OutputPath
)

begin {
    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
}

process {
    foreach ($computer in $ComputerName) {
        foreach ($p in $Port) {
            Write-Verbose "Testing $computer`:$p (timeout: ${Timeout}ms)"

            $tcpClient = New-Object -TypeName System.Net.Sockets.TcpClient
            $portOpen = $false

            try {
                $connectTask = $tcpClient.ConnectAsync($computer, $p)
                $waitResult = $connectTask.Wait($Timeout)

                if ($waitResult -and $tcpClient.Connected) {
                    $portOpen = $true
                }
            }
            catch {
                # Connection failed — port is closed or host unreachable
                $portOpen = $false
            }
            finally {
                $tcpClient.Dispose()
            }

            $allResults.Add([PSCustomObject]@{
                ComputerName = $computer
                Port         = $p
                Status       = if ($portOpen) { 'Open' } else { 'Closed' }
                Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            })

            $statusLabel = if ($portOpen) { 'Open' } else { 'Closed' }
            Write-Verbose "  $computer`:$p — $statusLabel"
        }
    }
}

end {
    if ($OutputPath) {
        $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported $($allResults.Count) port test results to $OutputPath"
    }
    else {
        Write-Output $allResults
    }
}
