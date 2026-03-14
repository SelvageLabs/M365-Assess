@{
    Severity = @('Error', 'Warning')

    Rules = @{
        PSAvoidUsingCmdletAliases              = @{ Enable = $true }
        PSAvoidUsingPositionalParameters       = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssignments    = @{ Enable = $true }
        PSAvoidUsingInvokeExpression            = @{ Enable = $true }
        PSAvoidUsingPlainTextForPassword        = @{ Enable = $true }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{ Enable = $true }
        PSUseProcessBlockForPipelineCommand     = @{ Enable = $true }
    }

    ExcludeRules = @(
        # Assessment uses Write-Host for console UX (progress, banners)
        'PSAvoidUsingWriteHost'
        # Read-only tool -- no state changes to protect with ShouldProcess
        'PSUseShouldProcessForStateChangingFunctions'
        # Collectors use $global:Update-CheckProgress by design
        'PSAvoidGlobalVars'
        # BOM encoding is a formatting preference, not a correctness issue
        'PSUseBOMForUnicodeEncodedFile'
        # High false-positive rate with orchestrators that pass params via splatting or inner scopes
        'PSReviewUnusedParameter'
        # Connect-Service intentionally converts client secret string to SecureString for credential objects
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
