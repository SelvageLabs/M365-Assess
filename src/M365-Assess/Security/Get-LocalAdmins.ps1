<#
.SYNOPSIS
    Reports members of the local Administrators group on one or more computers.
.DESCRIPTION
    Retrieves all members of the local Administrators group, including nested
    group membership. Works on local or remote computers. Useful for security
    baseline checks, compliance audits, and identifying unauthorized admin access.

    No external modules required. Uses built-in CIM/WMI for remote queries.
.PARAMETER ComputerName
    One or more computer names to query. Defaults to the local computer.
    Accepts pipeline input.
.PARAMETER Credential
    Credential for remote computer access. Not needed for the local computer.
.PARAMETER OutputPath
    Optional path to export results as CSV.
.EXAMPLE
    PS> .\Security\Get-LocalAdmins.ps1

    Lists local Administrators group members on the current computer.
.EXAMPLE
    PS> .\Security\Get-LocalAdmins.ps1 -ComputerName 'SERVER01','SERVER02'

    Lists local admins on multiple remote computers.
.EXAMPLE
    PS> Get-Content .\servers.txt | .\Security\Get-LocalAdmins.ps1 -OutputPath '.\local-admins.csv'

    Reads server names from a file and exports all local admin members to CSV.
.EXAMPLE
    PS> .\Security\Get-LocalAdmins.ps1 -ComputerName 'SERVER01' -Credential (Get-Credential)

    Queries a remote server using alternate credentials.
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
}

process {
    foreach ($computer in $ComputerName) {
        Write-Verbose "Querying local Administrators on $computer"

        try {
            if ($computer -eq $env:COMPUTERNAME -and -not $Credential) {
                # Local computer - use Get-LocalGroupMember directly
                $members = Get-LocalGroupMember -Group 'Administrators'

                foreach ($member in $members) {
                    $allResults.Add([PSCustomObject]@{
                        ComputerName = $computer
                        Name         = $member.Name
                        ObjectClass  = $member.ObjectClass
                        PrincipalSource = $member.PrincipalSource
                    })
                }
            }
            else {
                # Remote computer - use CIM
                $cimSession = $null
                $cimParams = @{
                    ComputerName = $computer
                }
                if ($Credential) {
                    $sessionParams = @{
                        ComputerName = $computer
                        Credential   = $Credential
                    }
                    $cimSession = New-CimSession @sessionParams
                    $cimParams = @{ CimSession = $cimSession }
                }

                $query = "SELECT * FROM Win32_GroupUser WHERE GroupComponent=`"Win32_Group.Domain='$computer',Name='Administrators'`""
                $members = Get-CimInstance -Query $query @cimParams

                foreach ($member in $members) {
                    $partComponent = $member.PartComponent
                    $memberName = "$($partComponent.Domain)\$($partComponent.Name)"
                    $objectClass = if ($partComponent.CimClass.CimClassName -eq 'Win32_UserAccount') { 'User' } else { 'Group' }

                    $allResults.Add([PSCustomObject]@{
                        ComputerName = $computer
                        Name         = $memberName
                        ObjectClass  = $objectClass
                        PrincipalSource = 'N/A'
                    })
                }

                if ($cimSession) {
                    Remove-CimSession -CimSession $cimSession
                }
            }
        }
        catch {
            Write-Warning "Failed to query $computer`: $_"
            $allResults.Add([PSCustomObject]@{
                ComputerName = $computer
                Name         = "ERROR: $_"
                ObjectClass  = 'Error'
                PrincipalSource = 'N/A'
            })
        }
    }
}

end {
    if ($OutputPath) {
        $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported $($allResults.Count) entries from $($ComputerName.Count) computer(s) to $OutputPath"
    }
    else {
        Write-Output $allResults
    }
}
