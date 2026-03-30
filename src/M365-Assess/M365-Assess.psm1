# M365-Assess module loader

# Dot-source orchestrator internal modules
Get-ChildItem -Path "$PSScriptRoot\Orchestrator\*.ps1" | ForEach-Object { . $_.FullName }

# Dot-source the main orchestrator to import Invoke-M365Assessment function
. $PSScriptRoot\Invoke-M365Assessment.ps1

Export-ModuleMember -Function 'Invoke-M365Assessment'
