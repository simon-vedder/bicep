#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies AVD / VDI optimizations to a Windows 10/11 golden image.
    Covers: FSLogix, Teams AVD mode, scheduled task cleanup, OS tuning.
    Based on Microsoft's Virtual Desktop Optimization Tool (VDOT) guidance.
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

Write-Output '[avd-optimizations] Starting AVD optimization...'

# ── FSLogix ───────────────────────────────────────────────────────────────────
Write-Output '[avd-optimizations] Installing FSLogix...'

$fslogixZip     = "$env:TEMP\FSLogix.zip"
$fslogixExtract = "$env:TEMP\FSLogix"
$fslogixUrl     = 'https://aka.ms/fslogix_download'

try {
    Invoke-WebRequest -Uri $fslogixUrl -OutFile $fslogixZip -UseBasicParsing -TimeoutSec 180
    Expand-Archive -Path $fslogixZip -DestinationPath $fslogixExtract -Force

    $installer = Get-ChildItem -Path $fslogixExtract -Filter 'FSLogixAppsSetup.exe' -Recurse | Select-Object -First 1
    if ($installer) {
        Start-Process -FilePath $installer.FullName -ArgumentList '/install /quiet /norestart' -Wait
        Write-Output '[avd-optimizations] FSLogix installed.'
    }
    else {
        Write-Warning '[avd-optimizations] FSLogix installer not found in archive.'
    }
}
catch {
    Write-Warning "[avd-optimizations] FSLogix install failed: $_"
}
finally {
    Remove-Item $fslogixZip, $fslogixExtract -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Teams AVD mode (per-machine install marker) ───────────────────────────────
Write-Output '[avd-optimizations] Configuring Teams for AVD...'

$teamsRegPath = 'HKLM:\SOFTWARE\Microsoft\Teams'
if (-not (Test-Path $teamsRegPath)) { New-Item -Path $teamsRegPath -Force | Out-Null }
Set-ItemProperty -Path $teamsRegPath -Name 'IsWVDEnvironment' -Value 1 -Type DWord

# New Teams (23H2+) uses a different key
$teamsNewPath = 'HKLM:\SOFTWARE\Microsoft\TeamsMeetingAddin'
if (-not (Test-Path $teamsNewPath)) { New-Item -Path $teamsNewPath -Force | Out-Null }
Set-ItemProperty -Path $teamsNewPath -Name 'IsWVDEnvironment' -Value 1 -Type DWord -ErrorAction SilentlyContinue

# ── Disable non-essential scheduled tasks ─────────────────────────────────────
Write-Output '[avd-optimizations] Disabling unnecessary scheduled tasks...'

$tasksToDisable = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Maps\MapsToastTask'
    '\Microsoft\Windows\Maps\MapsUpdateTask'
)

foreach ($task in $tasksToDisable) {
    $taskPath = Split-Path $task -Parent
    $taskName = Split-Path $task -Leaf
    Disable-ScheduledTask -TaskPath "$taskPath\" -TaskName $taskName -ErrorAction SilentlyContinue
}

# ── OS performance tuning ─────────────────────────────────────────────────────
Write-Output '[avd-optimizations] Applying OS performance settings...'

# High performance power plan
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# Disable hibernation (not applicable in VDI)
powercfg /hibernate off

# Disable Windows Search indexing service (reduces CPU/disk pressure in shared sessions)
Set-Service -Name WSearch -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue

# Disable Superfetch / SysMain (improves consistency in pooled VDI)
Set-Service -Name SysMain -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue

# Set visual effects to best performance
$visualEffectsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
if (-not (Test-Path $visualEffectsPath)) { New-Item -Path $visualEffectsPath -Force | Out-Null }
Set-ItemProperty -Path $visualEffectsPath -Name VisualFXSetting -Value 2 -Type DWord

# ── Remove non-essential inbox apps ──────────────────────────────────────────
Write-Output '[avd-optimizations] Removing non-essential inbox apps...'

$appsToRemove = @(
    'Microsoft.BingWeather'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.People'
    'Microsoft.WindowsMaps'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
)

foreach ($app in $appsToRemove) {
    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue |
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$app*" } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

Write-Output '[avd-optimizations] AVD optimization step complete.'
