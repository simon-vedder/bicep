#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies CIS-aligned security hardening to a Windows golden image.
    Covers: registry hardening, service disabling, firewall, SMB, NTLM, PrintNightmare mitigation.
    Level 1 controls. For full CIS compliance use the official CIS STIG kit post-deployment.

.NOTES
    Print Spooler is disabled here. Re-enable per image type if printing is required.
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

Write-Output '[security-hardening] Starting security hardening...'

# ── Disable unnecessary / high-risk services ──────────────────────────────────
Write-Output '[security-hardening] Disabling high-risk services...'

$servicesToDisable = @(
    'Spooler'         # PrintNightmare vector — disable if image does not need printing
    'RemoteRegistry'  # Remote registry access
    'TapiSrv'         # Telephony
    'Fax'
    'XblAuthManager'  # Xbox services
    'XblGameSave'
    'XboxNetApiSvc'
    'WerSvc'          # Windows Error Reporting (optional — disable for hardened envs)
)

foreach ($svc in $servicesToDisable) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Output "[security-hardening] Disabled: $svc"
    }
}

# ── Registry hardening ────────────────────────────────────────────────────────
Write-Output '[security-hardening] Applying registry hardening...'

$regSettings = @(
    # Disable AutoRun/AutoPlay
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoDriveTypeAutoRun'; Value = 255; Type = 'DWord' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer';                Name = 'NoAutoplayfornonVolume'; Value = 1;   Type = 'DWord' }

    # NTLM: require NTLMv2, refuse LM/NTLMv1
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LmCompatibilityLevel'; Value = 5; Type = 'DWord' }
    # Disable LM hash storage
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'NoLMHash'; Value = 1; Type = 'DWord' }

    # Disable SMBv1 (server side)
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; Name = 'SMB1'; Value = 0; Type = 'DWord' }
    # Require SMB signing
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; Name = 'RequireSecuritySignature'; Value = 1; Type = 'DWord' }
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name = 'RequireSecuritySignature'; Value = 1; Type = 'DWord' }

    # PrintNightmare mitigations
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'; Name = 'NoWarningNoElevationOnInstall'; Value = 0; Type = 'DWord' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'; Name = 'UpdatePromptSettings';          Value = 0; Type = 'DWord' }

    # Disable Cortana
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0; Type = 'DWord' }

    # Prevent storing credentials in plain text
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'DisableDomainCreds'; Value = 1; Type = 'DWord' }

    # Disable WDigest (prevents plain-text credential caching)
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Value = 0; Type = 'DWord' }

    # Enable LSA protection (Credential Guard prerequisite)
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RunAsPPL'; Value = 1; Type = 'DWord' }

    # Defender: ensure real-time protection is on
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRealtimeMonitoring'; Value = 0; Type = 'DWord' }
)

foreach ($reg in $regSettings) {
    if (-not (Test-Path $reg.Path)) {
        New-Item -Path $reg.Path -Force | Out-Null
    }
    Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type -ErrorAction SilentlyContinue
}

# ── Disable SMBv1 (client side via feature) ───────────────────────────────────
Write-Output '[security-hardening] Disabling SMBv1 Windows Feature...'
Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction SilentlyContinue

# ── Windows Firewall ──────────────────────────────────────────────────────────
Write-Output '[security-hardening] Enabling Windows Firewall for all profiles...'
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -ErrorAction SilentlyContinue

# ── TLS / Schannel hardening ──────────────────────────────────────────────────
Write-Output '[security-hardening] Disabling legacy TLS versions...'

$schannelBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'

foreach ($proto in @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1')) {
    foreach ($role in @('Client', 'Server')) {
        $path = "$schannelBase\$proto\$role"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name 'Enabled'            -Value 0 -Type DWord
        Set-ItemProperty -Path $path -Name 'DisabledByDefault'  -Value 1 -Type DWord
    }
}

# Ensure TLS 1.2 is explicitly enabled
foreach ($role in @('Client', 'Server')) {
    $path = "$schannelBase\TLS 1.2\$role"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name 'Enabled'           -Value 1 -Type DWord
    Set-ItemProperty -Path $path -Name 'DisabledByDefault' -Value 0 -Type DWord
}

Write-Output '[security-hardening] Security hardening step complete.'
