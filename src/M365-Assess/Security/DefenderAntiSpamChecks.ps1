# -------------------------------------------------------------------
# Defender -- Anti-Spam, Outbound Spam & Allowed Domains Checks
# Extracted from Get-DefenderSecurityConfig.ps1 (#257)
# Runs in shared scope: $settings, $checkIdCounter, Add-Setting,
#   Test-PresetPolicy, $script:presetPolicyNames
# -------------------------------------------------------------------
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

# ------------------------------------------------------------------
# 2. Anti-Spam Policies
# ------------------------------------------------------------------
try {
    Write-Verbose "Checking anti-spam policies..."
    $antiSpamPolicies = Get-HostedContentFilterPolicy -ErrorAction Stop

    foreach ($policy in @($antiSpamPolicies)) {
        $policyLabel = if ($policy.IsDefault) { 'Default' } else { $policy.Name }
        $presetTier = Test-PresetPolicy -PolicyName $policy.Name

        # Preset-managed policies enforce known-good values
        if ($presetTier) {
            $settingParams = @{
                Category         = 'Anti-Spam'
                Setting          = "Policy ($policyLabel)"
                CurrentValue     = "Managed by $presetTier preset security policy"
                RecommendedValue = 'Preset security policy active'
                Status           = 'Pass'
                CheckId          = 'DEFENDER-ANTISPAM-001'
                Remediation      = 'No action needed -- settings enforced by preset security policy.'
            }
            Add-Setting @settingParams
            continue
        }

        # Bulk complaint level threshold
        $bcl = $policy.BulkThreshold
        $settingParams = @{
            Category         = 'Anti-Spam'
            Setting          = "Bulk Complaint Level Threshold ($policyLabel)"
            CurrentValue     = "$bcl"
            RecommendedValue = '6 or lower'
            Status           = if ([int]$bcl -le 6) { 'Pass' } else { 'Warning' }
            CheckId          = 'DEFENDER-ANTISPAM-001'
            Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -BulkThreshold 6. Security admin center > Anti-spam > Inbound policy > Bulk email threshold > Set to 6 or lower.'
        }
        Add-Setting @settingParams

        # Spam action
        $spamAction = $policy.SpamAction
        $settingParams = @{
            Category         = 'Anti-Spam'
            Setting          = "Spam Action ($policyLabel)"
            CurrentValue     = "$spamAction"
            RecommendedValue = 'MoveToJmf or Quarantine'
            Status           = if ($spamAction -eq 'MoveToJmf' -or $spamAction -eq 'Quarantine') { 'Pass' } else { 'Warning' }
            CheckId          = 'DEFENDER-ANTISPAM-001'
            Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -SpamAction MoveToJmf. Security admin center > Anti-spam > Inbound policy > Spam action > Move to Junk Email folder.'
        }
        Add-Setting @settingParams

        # High confidence spam action
        $hcSpamAction = $policy.HighConfidenceSpamAction
        $settingParams = @{
            Category         = 'Anti-Spam'
            Setting          = "High Confidence Spam Action ($policyLabel)"
            CurrentValue     = "$hcSpamAction"
            RecommendedValue = 'Quarantine'
            Status           = if ($hcSpamAction -eq 'Quarantine') { 'Pass' } else { 'Warning' }
            CheckId          = 'DEFENDER-ANTISPAM-001'
            Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -HighConfidenceSpamAction Quarantine. Security admin center > Anti-spam > Inbound policy > High confidence spam action > Quarantine.'
        }
        Add-Setting @settingParams

        # High confidence phishing action
        $hcPhishAction = $policy.HighConfidencePhishAction
        $settingParams = @{
            Category         = 'Anti-Spam'
            Setting          = "High Confidence Phish Action ($policyLabel)"
            CurrentValue     = "$hcPhishAction"
            RecommendedValue = 'Quarantine'
            Status           = if ($hcPhishAction -eq 'Quarantine') { 'Pass' } else { 'Fail' }
            CheckId          = 'DEFENDER-ANTISPAM-001'
            Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -HighConfidencePhishAction Quarantine. Security admin center > Anti-spam > Inbound policy > High confidence phishing action > Quarantine.'
        }
        Add-Setting @settingParams

        # Phishing action
        $phishAction = $policy.PhishSpamAction
        $settingParams = @{
            Category         = 'Anti-Spam'
            Setting          = "Phishing Action ($policyLabel)"
            CurrentValue     = "$phishAction"
            RecommendedValue = 'Quarantine'
            Status           = if ($phishAction -eq 'Quarantine') { 'Pass' } else { 'Warning' }
            CheckId          = 'DEFENDER-ANTISPAM-001'
            Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -PhishSpamAction Quarantine. Security admin center > Anti-spam > Inbound policy > Phishing action > Quarantine.'
        }
        Add-Setting @settingParams

        # Zero-hour Auto Purge (ZAP)
        if ($null -ne $policy.ZapEnabled) {
            $zapEnabled = $policy.ZapEnabled
            $settingParams = @{
                Category         = 'Anti-Spam'
                Setting          = "Zero-Hour Auto Purge ($policyLabel)"
                CurrentValue     = "$zapEnabled"
                RecommendedValue = 'True'
                Status           = if ($zapEnabled) { 'Pass' } else { 'Fail' }
                CheckId          = 'DEFENDER-ANTISPAM-001'
                Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -ZapEnabled $true. Security admin center > Anti-spam > Inbound policy > Zero-hour auto purge > Enabled.'
            }
            Add-Setting @settingParams
        }

        # Spam ZAP
        if ($null -ne $policy.SpamZapEnabled) {
            $spamZap = $policy.SpamZapEnabled
            $settingParams = @{
                Category         = 'Anti-Spam'
                Setting          = "Spam ZAP ($policyLabel)"
                CurrentValue     = "$spamZap"
                RecommendedValue = 'True'
                Status           = if ($spamZap) { 'Pass' } else { 'Fail' }
                CheckId          = 'DEFENDER-ANTISPAM-001'
                Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -SpamZapEnabled $true. Security admin center > Anti-spam > Inbound policy > Zero-hour auto purge for spam > Enabled.'
            }
            Add-Setting @settingParams
        }

        # Phish ZAP
        if ($null -ne $policy.PhishZapEnabled) {
            $phishZap = $policy.PhishZapEnabled
            $settingParams = @{
                Category         = 'Anti-Spam'
                Setting          = "Phishing ZAP ($policyLabel)"
                CurrentValue     = "$phishZap"
                RecommendedValue = 'True'
                Status           = if ($phishZap) { 'Pass' } else { 'Fail' }
                CheckId          = 'DEFENDER-ANTISPAM-001'
                Remediation      = 'Run: Set-HostedContentFilterPolicy -Identity <PolicyName> -PhishZapEnabled $true. Security admin center > Anti-spam > Inbound policy > Zero-hour auto purge for phishing > Enabled.'
            }
            Add-Setting @settingParams
        }

        # Only assess default policy in detail
        if (-not $policy.IsDefault) { continue }
    }
}
catch {
    Write-Warning "Could not retrieve anti-spam policies: $_"
}

# ------------------------------------------------------------------
# 6. Outbound Spam Policy
# ------------------------------------------------------------------
try {
    Write-Verbose "Checking outbound spam policies..."
    $outboundPolicies = Get-HostedOutboundSpamFilterPolicy -ErrorAction Stop

    foreach ($policy in @($outboundPolicies)) {
        $policyLabel = if ($policy.IsDefault) { 'Default' } else { $policy.Name }

        # Auto-forwarding mode
        $autoForward = $policy.AutoForwardingMode
        $settingParams = @{
            Category         = 'Outbound Spam'
            Setting          = "Auto-Forwarding Mode ($policyLabel)"
            CurrentValue     = "$autoForward"
            RecommendedValue = 'Off'
            Status           = if ($autoForward -eq 'Off') { 'Pass' } else { 'Warning' }
            CheckId          = 'DEFENDER-OUTBOUND-001'
            Remediation      = 'Run: Set-HostedOutboundSpamFilterPolicy -Identity <PolicyName> -AutoForwardingMode Off. Security admin center > Anti-spam > Outbound policy > Auto-forwarding rules > Off.'
        }
        Add-Setting @settingParams

        # Notification
        if ($null -ne $policy.BccSuspiciousOutboundMail) {
            $bccNotify = $policy.BccSuspiciousOutboundMail
            $settingParams = @{
                Category         = 'Outbound Spam'
                Setting          = "BCC on Suspicious Outbound ($policyLabel)"
                CurrentValue     = "$bccNotify"
                RecommendedValue = 'True'
                Status           = if ($bccNotify) { 'Pass' } else { 'Warning' }
                CheckId          = 'DEFENDER-OUTBOUND-001'
                Remediation      = 'Run: Set-HostedOutboundSpamFilterPolicy -Identity <PolicyName> -BccSuspiciousOutboundMail $true -BccSuspiciousOutboundAdditionalRecipients admin@domain.com. Security admin center > Anti-spam > Outbound policy > Notifications > BCC suspicious outbound messages.'
            }
            Add-Setting @settingParams
        }

        if ($null -ne $policy.NotifyOutboundSpam) {
            $notifySpam = $policy.NotifyOutboundSpam
            $settingParams = @{
                Category         = 'Outbound Spam'
                Setting          = "Notify Admins of Outbound Spam ($policyLabel)"
                CurrentValue     = "$notifySpam"
                RecommendedValue = 'True'
                Status           = if ($notifySpam) { 'Pass' } else { 'Warning' }
                CheckId          = 'DEFENDER-OUTBOUND-001'
                Remediation      = 'Run: Set-HostedOutboundSpamFilterPolicy -Identity <PolicyName> -NotifyOutboundSpam $true -NotifyOutboundSpamRecipients admin@domain.com. Security admin center > Anti-spam > Outbound policy > Notifications > Notify admin of outbound spam.'
            }
            Add-Setting @settingParams
        }

        # Only assess default policy in detail
        if (-not $policy.IsDefault) { continue }
    }
}
catch {
    Write-Warning "Could not retrieve outbound spam policies: $_"
}

# ------------------------------------------------------------------
# 8. Anti-Spam Allowed Domains (CIS 2.1.14)
# ------------------------------------------------------------------
try {
    Write-Verbose "Checking anti-spam allowed sender domains..."
    # Reuse $antiSpamPolicies from section 2 if available
    if ($antiSpamPolicies) {
        foreach ($policy in @($antiSpamPolicies)) {
            $policyLabel = if ($policy.IsDefault) { 'Default' } else { $policy.Name }
            $allowedDomains = @($policy.AllowedSenderDomains)

            if ($allowedDomains.Count -eq 0) {
                $settingParams = @{
                    Category         = 'Anti-Spam'
                    Setting          = "Allowed Sender Domains ($policyLabel)"
                    CurrentValue     = '0 allowed domains'
                    RecommendedValue = 'No allowed domains'
                    Status           = 'Pass'
                    CheckId          = 'DEFENDER-ANTISPAM-002'
                    Remediation      = 'No action needed.'
                }
                Add-Setting @settingParams
            }
            else {
                $domainList = ($allowedDomains | Select-Object -First 10) -join ', '
                $suffix = if ($allowedDomains.Count -gt 10) { " (+$($allowedDomains.Count - 10) more)" } else { '' }
                $settingParams = @{
                    Category         = 'Anti-Spam'
                    Setting          = "Allowed Sender Domains ($policyLabel)"
                    CurrentValue     = "$($allowedDomains.Count) domains: $domainList$suffix"
                    RecommendedValue = 'No allowed domains'
                    Status           = 'Fail'
                    CheckId          = 'DEFENDER-ANTISPAM-002'
                    Remediation      = "Remove allowed sender domains: Set-HostedContentFilterPolicy -Identity '$policyLabel' -AllowedSenderDomains @{}. Security admin center > Anti-spam > Inbound policy > Allowed senders and domains > Remove all entries."
                }
                Add-Setting @settingParams
            }

            if (-not $policy.IsDefault) { continue }
        }
    }
}
catch {
    Write-Warning "Could not check anti-spam allowed domains: $_"
}
