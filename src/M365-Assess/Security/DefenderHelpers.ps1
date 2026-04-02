# -------------------------------------------------------------------
# Defender -- Helpers & Preset Policy Detection
# Extracted from Get-DefenderSecurityConfig.ps1 (#257)
# Runs in shared scope: $settings, $checkIdCounter, Add-Setting
# Exports: Test-PresetPolicy, $script:presetPolicyNames, $script:eopRules
# -------------------------------------------------------------------
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

function Test-PresetPolicy {
    param([string]$PolicyName)
    if ($script:presetPolicyNames.ContainsKey($PolicyName)) {
        return $script:presetPolicyNames[$PolicyName]
    }
    return $null
}

# ------------------------------------------------------------------
# Detect active preset security policies (Standard / Strict)
# Policies managed by presets enforce known-good values and should
# not be flagged as misconfigured when their property values differ
# from custom policy conventions.
# ------------------------------------------------------------------
$script:presetPolicyNames = @{}
$script:eopRules = @()
try {
    $eopRuleAvailable = Get-Command -Name Get-EOPProtectionPolicyRule -ErrorAction SilentlyContinue
    if ($eopRuleAvailable) {
        $script:eopRules = @(Get-EOPProtectionPolicyRule -ErrorAction Stop)
        foreach ($rule in $script:eopRules) {
            $tier = if ($rule.Identity -match 'Strict') { 'Strict' } elseif ($rule.Identity -match 'Standard') { 'Standard' } else { $null }
            if ($tier -and $rule.State -eq 'Enabled') {
                # Map exact policy names from the rule to their preset tier
                # Each rule references the specific policies it manages:
                #   HostedContentFilterPolicy, AntiPhishPolicy, MalwareFilterPolicy
                # These names include a numeric suffix (e.g., "Standard Preset Security Policy1774914322474")
                if ($rule.HostedContentFilterPolicy) { $script:presetPolicyNames[$rule.HostedContentFilterPolicy] = $tier }
                if ($rule.AntiPhishPolicy)            { $script:presetPolicyNames[$rule.AntiPhishPolicy] = $tier }
                if ($rule.MalwareFilterPolicy)        { $script:presetPolicyNames[$rule.MalwareFilterPolicy] = $tier }
            }
        }
        # Also check ATP rules for Safe Links / Safe Attachments
        $atpRuleAvailable = Get-Command -Name Get-ATPProtectionPolicyRule -ErrorAction SilentlyContinue
        if ($atpRuleAvailable) {
            $atpRules = @(Get-ATPProtectionPolicyRule -ErrorAction Stop)
            foreach ($rule in $atpRules) {
                $tier = if ($rule.Identity -match 'Strict') { 'Strict' } elseif ($rule.Identity -match 'Standard') { 'Standard' } else { $null }
                if ($tier -and $rule.State -eq 'Enabled') {
                    if ($rule.SafeLinksPolicy)       { $script:presetPolicyNames[$rule.SafeLinksPolicy] = $tier }
                    if ($rule.SafeAttachmentPolicy)   { $script:presetPolicyNames[$rule.SafeAttachmentPolicy] = $tier }
                }
            }
        }
        if ($script:presetPolicyNames.Count -gt 0) {
            Write-Verbose "Active preset-managed policies: $($script:presetPolicyNames.Keys -join ', ')"
        }
    }
}
catch {
    Write-Verbose "Could not query preset policy rules: $_"
}
