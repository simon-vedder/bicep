targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Name prefix for all resources (CAF naming). 3-15 chars, lowercase, hyphens allowed. Example: gib-contoso-prod')
@minLength(3)
@maxLength(15)
param namePrefix string

@description('Azure region for deployment.')
param location string = resourceGroup().location

param tags object = {
  solution: 'golden-image-builder'
  managedBy: 'bicep'
}

// Windows OS selection
@description('Build and maintain a Windows Server 2022 golden image.')
param enableWindowsServer2022 bool = true

@description('Build and maintain a Windows Server 2025 golden image.')
param enableWindowsServer2025 bool = true

@description('Build and maintain a Windows 11 Multi-Session golden image (AVD pooled hosts).')
param enableWindows11MultiSession bool = true

@description('Build and maintain a Windows 11 Single-Session golden image (AVD personal / standard VMs).')
param enableWindows11SingleSession bool = false

// Linux OS selection
@description('Build and maintain an Ubuntu 22.04 LTS golden image.')
param enableUbuntu2204 bool = false

@description('Build and maintain an Ubuntu 24.04 LTS golden image.')
param enableUbuntu2404 bool = false

@description('Build and maintain a RHEL 8 golden image.')
param enableRhel8 bool = false

@description('Build and maintain a RHEL 9 golden image.')
param enableRhel9 bool = false

// Customization
@description('Install Azure Monitor Agent during image build.')
param installAzureMonitorAgent bool = true

@description('Install Microsoft Defender for Endpoint prerequisites during image build.')
param installDefenderForEndpoint bool = true

@description('Apply CIS-aligned security hardening.')
param enableSecurityHardening bool = false

@description('Apply AVD-specific optimizations (FSLogix, Teams, OS tweaks). Applied to Win11 images only.')
param enableAvdOptimizations bool = true

// Script sources
@description('Base URL for Windows PowerShell customization scripts.')
param windowsScriptBaseUrl string = 'https://raw.githubusercontent.com/simon-vedder/bicep/add/goldenimagebuilder/automations/build-golden-image/windows/scripts'

@description('Base URL for Linux shell customization scripts.')
param linuxScriptBaseUrl string = 'https://raw.githubusercontent.com/simon-vedder/bicep/add/goldenimagebuilder/automations/build-golden-image/linux/scripts'

@description('Use a private Azure Blob container for scripts instead of GitHub.')
param usePrivateScriptStorage bool = false

// Schedule
@description('Day of month to run the scheduled build (1-28). Default 15 = ~3 days after Patch Tuesday.')
@minValue(1)
@maxValue(28)
param buildScheduleDayOfMonth int = 15

@description('Hour (UTC) to start the scheduled build (0-23). Default 2 = 02:00 UTC.')
@minValue(0)
@maxValue(23)
param buildScheduleHour int = 2

// Networking
@description('Inject the AIB build VM into a customer VNet.')
param useVNetInjection bool = false

param vnetResourceGroupName string = ''
param vnetName string = ''
param subnetName string = ''

// Notifications & monitoring
@description('Email address for build success/failure notifications. Leave empty to disable.')
param notificationEmail string = ''

@description('Deploy a Log Analytics workspace for build monitoring.')
param enableLogAnalytics bool = false

// Replication
@description('Additional Azure regions to replicate image versions into.')
param additionalReplicationRegions array = []

// ── Shared modules ────────────────────────────────────────────────────────────

module identity 'shared/modules/identity.bicep' = {
  name: 'identity'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

module gallery 'shared/modules/gallery.bicep' = {
  name: 'gallery'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
    enableWindowsServer2022: enableWindowsServer2022
    enableWindowsServer2025: enableWindowsServer2025
    enableWindows11MultiSession: enableWindows11MultiSession
    enableWindows11SingleSession: enableWindows11SingleSession
    enableUbuntu2204: enableUbuntu2204
    enableUbuntu2404: enableUbuntu2404
    enableRhel8: enableRhel8
    enableRhel9: enableRhel9
  }
}

// ── Role assignments ──────────────────────────────────────────────────────────

var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource aibContributorRa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'uami-${namePrefix}-aib', contributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: identity.outputs.aibIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource laContributorRa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'uami-${namePrefix}-la', contributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: identity.outputs.logicAppIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ── Image configurations ──────────────────────────────────────────────────────

var windowsImageConfigs = [
  {
    enabled: enableWindowsServer2022
    name: 'ws2022'
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    isAvd: false
  }
  {
    enabled: enableWindowsServer2025
    name: 'ws2025'
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2025-datacenter-azure-edition'
    isAvd: false
  }
  {
    enabled: enableWindows11MultiSession
    name: 'win11-ms'
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-11'
    sku: 'win11-24h2-avd'
    isAvd: true
  }
  {
    enabled: enableWindows11SingleSession
    name: 'win11-ss'
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-11'
    sku: 'win11-24h2-ent'
    isAvd: true
  }
]

var linuxImageConfigs = [
  {
    enabled: enableUbuntu2204
    name: 'ubuntu2204'
    publisher: 'Canonical'
    offer: '0001-com-ubuntu-server-jammy'
    sku: '22_04-lts-gen2'
  }
  {
    enabled: enableUbuntu2404
    name: 'ubuntu2404'
    publisher: 'Canonical'
    offer: 'ubuntu-24_04-lts'
    sku: 'server'
  }
  {
    enabled: enableRhel8
    name: 'rhel8'
    publisher: 'RedHat'
    offer: 'RHEL'
    sku: '8-lvm-gen2'
  }
  {
    enabled: enableRhel9
    name: 'rhel9'
    publisher: 'RedHat'
    offer: 'RHEL'
    sku: '9-lvm-gen2'
  }
]

var enabledWindowsConfigs = filter(windowsImageConfigs, c => c.enabled)
var enabledLinuxConfigs = filter(linuxImageConfigs, c => c.enabled)

var storageAccountName = toLower(take('stgib${replace(replace(namePrefix, '-', ''), '_', '')}', 24))
var blobScriptUrl = 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts'

var resolvedWindowsScriptBaseUrl = usePrivateScriptStorage ? blobScriptUrl : windowsScriptBaseUrl
var resolvedLinuxScriptBaseUrl = usePrivateScriptStorage ? blobScriptUrl : linuxScriptBaseUrl

// ── Windows image templates ───────────────────────────────────────────────────

module windowsImageTemplates 'windows/modules/imageTemplate.bicep' = [for config in enabledWindowsConfigs: {
  name: 'imageTemplate-${config.name}'
  params: {
    location: location
    namePrefix: namePrefix
    imageName: config.name
    imagePublisher: config.publisher
    imageOffer: config.offer
    imageSku: config.sku
    isAvd: config.isAvd
    aibIdentityId: identity.outputs.aibIdentityId
    galleryName: gallery.outputs.galleryName
    scriptBaseUrl: resolvedWindowsScriptBaseUrl
    installAzureMonitorAgent: installAzureMonitorAgent
    installDefenderForEndpoint: installDefenderForEndpoint
    enableSecurityHardening: enableSecurityHardening
    enableAvdOptimizations: enableAvdOptimizations && config.isAvd
    useVNetInjection: useVNetInjection
    vnetResourceGroupName: vnetResourceGroupName
    vnetName: vnetName
    subnetName: subnetName
    replicationRegions: additionalReplicationRegions
    tags: tags
  }
  dependsOn: [aibContributorRa, storage]
}]

// ── Linux image templates ─────────────────────────────────────────────────────

module linuxImageTemplates 'linux/modules/imageTemplate.bicep' = [for config in enabledLinuxConfigs: {
  name: 'imageTemplate-${config.name}'
  params: {
    location: location
    namePrefix: namePrefix
    imageName: config.name
    imagePublisher: config.publisher
    imageOffer: config.offer
    imageSku: config.sku
    aibIdentityId: identity.outputs.aibIdentityId
    galleryName: gallery.outputs.galleryName
    scriptBaseUrl: resolvedLinuxScriptBaseUrl
    installAzureMonitorAgent: installAzureMonitorAgent
    installDefenderForEndpoint: installDefenderForEndpoint
    enableSecurityHardening: enableSecurityHardening
    useVNetInjection: useVNetInjection
    vnetResourceGroupName: vnetResourceGroupName
    vnetName: vnetName
    subnetName: subnetName
    replicationRegions: additionalReplicationRegions
    tags: tags
  }
  dependsOn: [aibContributorRa, storage]
}]

// ── Logic App (schedule + manual trigger) ─────────────────────────────────────

var enabledWindowsTemplateNames = [for config in enabledWindowsConfigs: 'aib-${namePrefix}-${config.name}']
var enabledLinuxTemplateNames = [for config in enabledLinuxConfigs: 'aib-${namePrefix}-${config.name}']
var allTemplateNames = concat(enabledWindowsTemplateNames, enabledLinuxTemplateNames)

module logicApp 'shared/modules/logicapp.bicep' = {
  name: 'logicapp'
  params: {
    location: location
    namePrefix: namePrefix
    logicAppIdentityId: identity.outputs.logicAppIdentityId
    imageTemplateNames: allTemplateNames
    buildScheduleDayOfMonth: buildScheduleDayOfMonth
    buildScheduleHour: buildScheduleHour
    subscriptionId: subscription().subscriptionId
    resourceGroupName: resourceGroup().name
    tags: tags
  }
  dependsOn: [windowsImageTemplates, linuxImageTemplates, laContributorRa]
}

// ── Optional: private script storage ─────────────────────────────────────────

module storage 'shared/modules/storage.bicep' = if (usePrivateScriptStorage) {
  name: 'storage'
  params: {
    location: location
    namePrefix: namePrefix
    aibIdentityPrincipalId: identity.outputs.aibIdentityPrincipalId
    scriptSourceBaseUrl: windowsScriptBaseUrl
    scriptFileNames: ['windows-updates.ps1', 'install-agents.ps1', 'avd-optimizations.ps1', 'security-hardening.ps1']
    secondaryScriptSourceBaseUrl: linuxScriptBaseUrl
    secondaryScriptFileNames: ['linux-updates.sh', 'install-ama.sh', 'install-mde.sh', 'security-hardening.sh']
    tags: tags
  }
}

// ── Optional: monitoring ──────────────────────────────────────────────────────

module monitoring 'shared/modules/monitoring.bicep' = if (enableLogAnalytics || !empty(notificationEmail)) {
  name: 'monitoring'
  params: {
    location: location
    namePrefix: namePrefix
    notificationEmail: notificationEmail
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output galleryName string = gallery.outputs.galleryName
output galleryId string = gallery.outputs.galleryId
output deployedImageTemplates array = allTemplateNames
@description('POST to this URL to manually trigger a build cycle for all image templates.')
output manualTriggerUrl string = logicApp.outputs.runnerTriggerUrl
output aibIdentityId string = identity.outputs.aibIdentityId
