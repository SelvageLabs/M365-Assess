# -------------------------------------------------------------------
# Defender -- Safe Links & Safe Attachments Checks
# Extracted from Get-DefenderSecurityConfig.ps1 (#257)
# Runs in shared scope: $settings, $checkIdCounter, Add-Setting,
#   Test-PresetPolicy, $script:presetPolicyNames
# -------------------------------------------------------------------
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# ------------------------------------------------------------------
# 4. Safe Links Policies (Defender P1+)
# ------------------------------------------------------------------
try {
    $slAvailable = Get-Command -Name Get-SafeLinksPolicy -ErrorAction SilentlyContinue
    if ($slAvailable) {
        Write-Verbose "Checking Safe Links policies..."
        $safeLinks = Get-SafeLinksPolicy -ErrorAction Stop

        if (@($safeLinks).Count -eq 0) {
            $settingParams = @{
                Category         = 'Safe Links'
                Setting          = 'Safe Links Policies'
                CurrentValue     = 'None configured'
                RecommendedValue = 'At least 1 policy'
                Status           = 'Warning'
                CheckId          = 'DEFENDER-SAFELINKS-001'
                Remediation      = 'Run: New-SafeLinksPolicy -Name "Safe Links" -IsEnabled $true; New-SafeLinksRule -Name "Safe Links" -SafeLinksPolicy "Safe Links" -RecipientDomainIs (Get-AcceptedDomain).Name. Security admin center > Safe Links > Create a policy covering all users.'
            }
            Add-Setting @settingParams
        }
        else {
            foreach ($policy in @($safeLinks)) {
                $policyLabel = $policy.Name
                $presetTier = Test-PresetPolicy -PolicyName $policy.Name
                if ($presetTier) {
                    $settingParams = @{
                        Category         = 'Safe Links'
                        Setting          = "Policy ($policyLabel)"
                        CurrentValue     = "Managed by $presetTier preset security policy"
                        RecommendedValue = 'Preset security policy active'
                        Status           = 'Pass'
                        CheckId          = 'DEFENDER-SAFELINKS-001'
                        Remediation      = 'No action needed -- settings enforced by preset security policy.'
                    }
                    Add-Setting @settingParams
                    continue
                }

                # URL scanning
                $scanUrls = $policy.ScanUrls
                $settingParams = @{
                    Category         = 'Safe Links'
                    Setting          = "Real-time URL Scanning ($policyLabel)"
                    CurrentValue     = "$scanUrls"
                    RecommendedValue = 'True'
                    Status           = if ($scanUrls) { 'Pass' } else { 'Warning' }
                    CheckId          = 'DEFENDER-SAFELINKS-001'
                    Remediation      = 'Run: Set-SafeLinksPolicy -Identity <PolicyName> -ScanUrls $true. Security admin center > Safe Links policy > URL & click protection > Enable real-time URL scanning.'
                }
                Add-Setting @settingParams

                # Click tracking
                $trackClicks = -not $policy.DoNotTrackUserClicks
                $settingParams = @{
                    Category         = 'Safe Links'
                    Setting          = "Track User Clicks ($policyLabel)"
                    CurrentValue     = "$trackClicks"
                    RecommendedValue = 'True'
                    Status           = if ($trackClicks) { 'Pass' } else { 'Warning' }
                    CheckId          = 'DEFENDER-SAFELINKS-001'
                    Remediation      = 'Run: Set-SafeLinksPolicy -Identity <PolicyName> -DoNotTrackUserClicks $false. Security admin center > Safe Links policy > Ensure "Do not track when users click protected links" is disabled.'
                }
                Add-Setting @settingParams

                # Internal senders
                if ($null -ne $policy.EnableForInternalSenders) {
                    $internalSenders = $policy.EnableForInternalSenders
                    $settingParams = @{
                        Category         = 'Safe Links'
                        Setting          = "Enable for Internal Senders ($policyLabel)"
                        CurrentValue     = "$internalSenders"
                        RecommendedValue = 'True'
                        Status           = if ($internalSenders) { 'Pass' } else { 'Warning' }
                        CheckId          = 'DEFENDER-SAFELINKS-001'
                        Remediation      = 'Run: Set-SafeLinksPolicy -Identity <PolicyName> -EnableForInternalSenders $true. Security admin center > Safe Links policy > Enable for messages sent within the organization.'
                    }
                    Add-Setting @settingParams
                }

                # Wait for URL scanning
                if ($null -ne $policy.DeliverMessageAfterScan) {
                    $waitScan = $policy.DeliverMessageAfterScan
                    $settingParams = @{
                        Category         = 'Safe Links'
                        Setting          = "Wait for URL Scan ($policyLabel)"
                        CurrentValue     = "$waitScan"
                        RecommendedValue = 'True'
                        Status           = if ($waitScan) { 'Pass' } else { 'Warning' }
                        CheckId          = 'DEFENDER-SAFELINKS-001'
                        Remediation      = 'Run: Set-SafeLinksPolicy -Identity <PolicyName> -DeliverMessageAfterScan $true. Security admin center > Safe Links policy > Wait for URL scanning to complete before delivering the message.'
                    }
                    Add-Setting @settingParams
                }
            }
        }
    }
    else {
        $settingParams = @{
            Category         = 'Safe Links'
            Setting          = 'Safe Links Availability'
            CurrentValue     = 'Not licensed'
            RecommendedValue = 'Defender for Office 365 P1+'
            Status           = 'Review'
            CheckId          = 'DEFENDER-SAFELINKS-001'
            Remediation      = 'Safe Links requires Defender for Office 365 Plan 1 or higher.'
        }
        Add-Setting @settingParams
    }
}
catch {
    Write-Warning "Could not retrieve Safe Links policies: $_"
}

# ------------------------------------------------------------------
# 5. Safe Attachments Policies (Defender P1+)
# ------------------------------------------------------------------
try {
    $saAvailable = Get-Command -Name Get-SafeAttachmentPolicy -ErrorAction SilentlyContinue
    if ($saAvailable) {
        Write-Verbose "Checking Safe Attachments policies..."
        $safeAttachments = Get-SafeAttachmentPolicy -ErrorAction Stop

        if (@($safeAttachments).Count -eq 0) {
            $settingParams = @{
                Category         = 'Safe Attachments'
                Setting          = 'Safe Attachments Policies'
                CurrentValue     = 'None configured'
                RecommendedValue = 'At least 1 policy'
                Status           = 'Warning'
                CheckId          = 'DEFENDER-SAFEATTACH-001'
                Remediation      = 'Run: New-SafeAttachmentPolicy -Name "Safe Attachments" -Enable $true -Action Block; New-SafeAttachmentRule -Name "Safe Attachments" -SafeAttachmentPolicy "Safe Attachments" -RecipientDomainIs (Get-AcceptedDomain).Name. Security admin center > Safe Attachments > Create a policy covering all users.'
            }
            Add-Setting @settingParams
        }
        else {
            foreach ($policy in @($safeAttachments)) {
                $policyLabel = $policy.Name
                $presetTier = Test-PresetPolicy -PolicyName $policy.Name
                if ($presetTier) {
                    $settingParams = @{
                        Category         = 'Safe Attachments'
                        Setting          = "Policy ($policyLabel)"
                        CurrentValue     = "Managed by $presetTier preset security policy"
                        RecommendedValue = 'Preset security policy active'
                        Status           = 'Pass'
                        CheckId          = 'DEFENDER-SAFEATTACH-001'
                        Remediation      = 'No action needed -- settings enforced by preset security policy.'
                    }
                    Add-Setting @settingParams
                    continue
                }

                # Enabled
                $enabled = $policy.Enable
                $settingParams = @{
                    Category         = 'Safe Attachments'
                    Setting          = "Policy Enabled ($policyLabel)"
                    CurrentValue     = "$enabled"
                    RecommendedValue = 'True'
                    Status           = if ($enabled) { 'Pass' } else { 'Warning' }
                    CheckId          = 'DEFENDER-SAFEATTACH-001'
                    Remediation      = 'Run: Set-SafeAttachmentPolicy -Identity <PolicyName> -Enable $true. Security admin center > Safe Attachments policy > Enable the policy.'
                }
                Add-Setting @settingParams

                # Action type
                $action = $policy.Action
                $actionDisplay = switch ($action) {
                    'Allow'            { 'Allow (no scanning)' }
                    'Block'            { 'Block' }
                    'Replace'          { 'Replace attachment' }
                    'DynamicDelivery'  { 'Dynamic Delivery' }
                    default { $action }
                }

                $actionStatus = switch ($action) {
                    'Allow'           { 'Fail' }
                    'Block'           { 'Pass' }
                    'Replace'         { 'Pass' }
                    'DynamicDelivery' { 'Pass' }
                    default { 'Review' }
                }

                $settingParams = @{
                    Category         = 'Safe Attachments'
                    Setting          = "Action ($policyLabel)"
                    CurrentValue     = $actionDisplay
                    RecommendedValue = 'Block or Dynamic Delivery'
                    Status           = $actionStatus
                    CheckId          = 'DEFENDER-SAFEATTACH-001'
                    Remediation      = 'Run: Set-SafeAttachmentPolicy -Identity <PolicyName> -Action Block. Security admin center > Safe Attachments policy > Action > Block (or DynamicDelivery for user experience).'
                }
                Add-Setting @settingParams

                # Redirect
                $redirect = $policy.Redirect
                $settingParams = @{
                    Category         = 'Safe Attachments'
                    Setting          = "Redirect to Admin ($policyLabel)"
                    CurrentValue     = "$redirect"
                    RecommendedValue = 'True'
                    Status           = if ($redirect) { 'Pass' } else { 'Warning' }
                    CheckId          = 'DEFENDER-SAFEATTACH-001'
                    Remediation      = 'Run: Set-SafeAttachmentPolicy -Identity <PolicyName> -Redirect $true -RedirectAddress admin@domain.com. Security admin center > Safe Attachments policy > Enable redirect and specify an admin email.'
                }
                Add-Setting @settingParams
            }
        }
    }
    else {
        $settingParams = @{
            Category         = 'Safe Attachments'
            Setting          = 'Safe Attachments Availability'
            CurrentValue     = 'Not licensed'
            RecommendedValue = 'Defender for Office 365 P1+'
            Status           = 'Review'
            CheckId          = 'DEFENDER-SAFEATTACH-001'
            Remediation      = 'Safe Attachments requires Defender for Office 365 Plan 1 or higher.'
        }
        Add-Setting @settingParams
    }
}
catch {
    Write-Warning "Could not retrieve Safe Attachments policies: $_"
}

# ------------------------------------------------------------------
# 5b. Safe Attachments for SPO/OneDrive/Teams (CIS 2.1.5)
# ------------------------------------------------------------------
try {
    $atpO365Available = Get-Command -Name Get-AtpPolicyForO365 -ErrorAction SilentlyContinue
    if ($atpO365Available) {
        Write-Verbose "Checking Safe Attachments for SPO/OneDrive/Teams..."
        $atpPolicy = Get-AtpPolicyForO365 -ErrorAction Stop

        $atpEnabled = $atpPolicy.EnableATPForSPOTeamsODB
        $settingParams = @{
            Category         = 'Safe Attachments'
            Setting          = 'Safe Attachments for SPO/OneDrive/Teams'
            CurrentValue     = "$atpEnabled"
            RecommendedValue = 'True'
            Status           = if ($atpEnabled) { 'Pass' } else { 'Fail' }
            CheckId          = 'DEFENDER-SAFEATTACH-002'
            Remediation      = 'Run: Set-AtpPolicyForO365 -EnableATPForSPOTeamsODB $true. Security admin center > Safe Attachments > Global settings > Turn on Defender for Office 365 for SharePoint, OneDrive, and Microsoft Teams.'
        }
        Add-Setting @settingParams
    }
    else {
        $settingParams = @{
            Category         = 'Safe Attachments'
            Setting          = 'Safe Attachments for SPO/OneDrive/Teams'
            CurrentValue     = 'Not licensed'
            RecommendedValue = 'Defender for Office 365 P1+'
            Status           = 'Review'
            CheckId          = 'DEFENDER-SAFEATTACH-002'
            Remediation      = 'Safe Attachments for SPO/OneDrive/Teams requires Defender for Office 365 Plan 1 or higher.'
        }
        Add-Setting @settingParams
    }
}
catch {
    Write-Warning "Could not check Safe Attachments for SPO/OneDrive/Teams: $_"
}
