#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs all pending Windows Updates during an AIB build.
    Excludes preview/optional updates. Safe to run multiple times.
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Write-Output '[windows-updates] Starting Windows Update installation...'

# Ensure NuGet provider available (required by PSWindowsUpdate)
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

# Install PSWindowsUpdate module if not present
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -Confirm:$false
}

Import-Module PSWindowsUpdate -Force

# Install all non-preview updates — suppress reboot (AIB handles restarts via WindowsRestart step)
$result = Install-WindowsUpdate `
    -MicrosoftUpdate `
    -AcceptAll `
    -IgnoreReboot `
    -NotTitle 'Preview' `
    -Verbose `
    -ErrorAction Continue

Write-Output "[windows-updates] Updates installed: $($result.Count)"
Write-Output '[windows-updates] Windows Update step complete.'
