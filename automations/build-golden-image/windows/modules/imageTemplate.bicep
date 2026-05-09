@description('Azure region.')
param location string

@description('CAF name prefix.')
param namePrefix string

@description('Short OS identifier: ws2022 | ws2025 | win11-ms | win11-ss')
param imageName string

param imagePublisher string
param imageOffer string
param imageSku string
param imageVersion string = 'latest'

@description('True for Windows 10/11 images — enables AVD-specific customization path.')
param isAvd bool = false

@description('Resource ID of the AIB user-assigned managed identity.')
param aibIdentityId string

@description('Name of the Azure Compute Gallery.')
param galleryName string

@description('Base URL for PowerShell scripts (raw GitHub path or blob container URL).')
param scriptBaseUrl string

param installAzureMonitorAgent bool = true
param installDefenderForEndpoint bool = true
param enableSecurityHardening bool = false
param enableAvdOptimizations bool = false

param useVNetInjection bool = false
param vnetResourceGroupName string = ''
param vnetName string = ''
param subnetName string = ''

@description('Additional replication regions beyond the deployment region.')
param replicationRegions array = []

param tags object = {}

var templateName = 'aib-${namePrefix}-${imageName}'
var imageDefinitionName = 'imgdef-${namePrefix}-${imageName}'

// ── Customization steps ──────────────────────────────────────────────────────

var updatesSteps = [
  {
    type: 'PowerShell'
    name: 'WindowsUpdates'
    scriptUri: '${scriptBaseUrl}/windows-updates.ps1'
    runElevated: true
    runAsSystem: true
  }
  {
    type: 'WindowsRestart'
    restartCommand: 'shutdown /r /f /t 0'
    restartCheckCommand: 'echo Restart complete'
    restartTimeout: '10m'
  }
]

var agentSteps = (installAzureMonitorAgent || installDefenderForEndpoint) ? [
  {
    type: 'PowerShell'
    name: 'InstallAgents'
    scriptUri: '${scriptBaseUrl}/install-agents.ps1'
    runElevated: true
    runAsSystem: true
    validExitCodes: [0, 3010]
  }
] : []

var securitySteps = enableSecurityHardening ? [
  {
    type: 'PowerShell'
    name: 'SecurityHardening'
    scriptUri: '${scriptBaseUrl}/security-hardening.ps1'
    runElevated: true
    runAsSystem: true
  }
] : []

var avdSteps = (isAvd && enableAvdOptimizations) ? [
  {
    type: 'PowerShell'
    name: 'AvdOptimizations'
    scriptUri: '${scriptBaseUrl}/avd-optimizations.ps1'
    runElevated: true
    runAsSystem: true
  }
] : []

var finalRestartStep = [
  {
    type: 'WindowsRestart'
    restartCommand: 'shutdown /r /f /t 0'
    restartCheckCommand: 'echo Final restart complete'
    restartTimeout: '5m'
  }
]

var allCustomizations = concat(updatesSteps, agentSteps, securitySteps, avdSteps, finalRestartStep)

// ── VNet config (conditional) ────────────────────────────────────────────────

var vmProfileBase = {
  vmSize: 'Standard_D4s_v3'
  osDiskSizeGB: 128
}

var vmProfile = useVNetInjection ? union(vmProfileBase, {
  vnetConfig: {
    subnetId: resourceId(vnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
  }
}) : vmProfileBase

// ── Replication regions ──────────────────────────────────────────────────────

var allRegions = union([location], replicationRegions)

// ── Existing resources ───────────────────────────────────────────────────────

resource gallery 'Microsoft.Compute/galleries@2023-07-03' existing = {
  name: galleryName
}

resource imageDefinition 'Microsoft.Compute/galleries/images@2023-07-03' existing = {
  parent: gallery
  name: imageDefinitionName
}

// ── AIB Image Template ───────────────────────────────────────────────────────

resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2024-02-01' = {
  name: templateName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aibIdentityId}': {}
    }
  }
  properties: {
    buildTimeoutInMinutes: 120
    vmProfile: vmProfile
    source: {
      type: 'PlatformImage'
      publisher: imagePublisher
      offer: imageOffer
      sku: imageSku
      version: imageVersion
    }
    customize: allCustomizations
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: imageDefinition.id
        runOutputName: '${templateName}-output'
        replicationRegions: allRegions
        storageAccountType: 'Standard_LRS'
        excludeFromLatest: false
      }
    ]
    errorHandling: {
      onCustomizerError: 'cleanup'
      onValidationError: 'cleanup'
    }
  }
}

output imageTemplateId string = imageTemplate.id
output imageTemplateName string = imageTemplate.name
