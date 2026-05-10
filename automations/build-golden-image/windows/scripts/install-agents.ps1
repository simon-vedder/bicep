#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Azure Monitor Agent and/or Defender for Endpoint prerequisites.
    Controlled by environment variables set via AIB customize block env vars
    or falls back to defaults (both enabled).

    INSTALL_AMA  = '1' | '0'   (default: 1)
    INSTALL_MDE  = '1' | '0'   (default: 1)

.NOTES
    MDE full onboarding requires an org-specific onboarding package applied
    post-deployment via Intune, Defender portal, or Group Policy.
    This script pre-stages prerequisites and enables real-time protection.
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

$installAma = ($env:INSTALL_AMA -ne '0')   # default on unless explicitly '0'
$installMde = ($env:INSTALL_MDE -ne '0')

# ── Azure Monitor Agent ───────────────────────────────────────────────────────
if ($installAma) {
    Write-Output '[install-agents] Installing Azure Monitor Agent...'

    # Download the MSI installer
    $amaInstaller = "$env:TEMP\AzureMonitorAgentSetup.msi"
    $amaUrl = 'https://download.microsoft.com/download/azure-monitor-agent/AzureMonitorAgentSetup.msi'

    try {
        Invoke-WebRequest -Uri $amaUrl -OutFile $amaInstaller -UseBasicParsing -TimeoutSec 120
        Start-Process msiexec.exe -ArgumentList "/i `"$amaInstaller`" /quiet /norestart" -Wait -PassThru
        Remove-Item $amaInstaller -Force -ErrorAction SilentlyContinue
        Write-Output '[install-agents] Azure Monitor Agent installed.'
    }
    catch {
        # AMA is commonly deployed as a VM extension post-deployment.
        # Log the failure but do not abort the build.
        Write-Warning "[install-agents] AMA install failed: $_"
        Write-Warning '[install-agents] AMA can be deployed as a VM extension after VM creation.'
    }
}

# ── Microsoft Defender for Endpoint prerequisites ─────────────────────────────
if ($installMde) {
    Write-Output '[install-agents] Configuring Defender for Endpoint prerequisites...'

    # Ensure Windows Defender is enabled and up to date
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Update-MpSignature -ErrorAction SilentlyContinue
        Write-Output '[install-agents] Defender real-time protection enabled, signatures updated.'
    }
    catch {
        Write-Warning "[install-agents] Defender config failed: $_"
    }

    # Install MDE onboarding prerequisites (Sense service must be present on Server SKUs)
    $senseService = Get-Service -Name Sense -ErrorAction SilentlyContinue
    if (-not $senseService) {
        Write-Output '[install-agents] Sense service not found — MDE full onboarding package must be applied post-deployment.'
        Write-Output '[install-agents] Reference: https://learn.microsoft.com/defender-endpoint/onboard-windows-server'
    }
    else {
        Write-Output '[install-agents] Sense service present — MDE onboarding package can be applied post-deployment.'
    }
}

Write-Output '[install-agents] Agent installation step complete.'
