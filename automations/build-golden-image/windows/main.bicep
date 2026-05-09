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

// OS selection
@description('Build and maintain a Windows Server 2022 golden image.')
param enableWindowsServer2022 bool = true

@description('Build and maintain a Windows Server 2025 golden image.')
param enableWindowsServer2025 bool = true

@description('Build and maintain a Windows 11 Multi-Session golden image (AVD pooled hosts).')
param enableWindows11MultiSession bool = true

@description('Build and maintain a Windows 11 Single-Session golden image (AVD personal / standard VMs).')
param enableWindows11SingleSession bool = true

// Customization
@description('Install Azure Monitor Agent during image build.')
param installAzureMonitorAgent bool = true

@description('Install Microsoft Defender for Endpoint prerequisites during image build.')
param installDefenderForEndpoint bool = true

@description('Apply CIS-aligned security hardening (registry, services, firewall).')
param enableSecurityHardening bool = false

@description('Apply AVD-specific optimizations (FSLogix, Teams, OS tweaks). Applied to Win11 images only.')
param enableAvdOptimizations bool = true

// Script source
@description('Base URL for PowerShell customization scripts. Change only if using a fork or private storage.')
param scriptBaseUrl string = 'https://raw.githubusercontent.com/simon-vedder/bicep/add/goldenimagebuilder/automations/build-golden-image/windows/scripts'

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
@description('Inject the AIB build VM into a customer VNet (required for private script storage or strict outbound rules).')
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

module identity '../shared/modules/identity.bicep' = {
  name: 'identity'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

module gallery '../shared/modules/gallery.bicep' = {
  name: 'gallery'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
    enableWindowsServer2022: enableWindowsServer2022
    enableWindowsServer2025: enableWindowsServer2025
    enableWindows11MultiSession: enableWindows11MultiSession
    enableWindows11SingleSession: enableWindows11SingleSession
  }
}

// ── Role assignments ──────────────────────────────────────────────────────────
// Contributor on this RG for both UAMIs.
// Production: scope down to custom roles with least privilege.

var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// guid() seed uses UAMI name — known at deploy start, unlike principalId (runtime value)
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

var imageConfigs = [
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

var enabledImageConfigs = filter(imageConfigs, config => config.enabled)

// Derive private script URL from naming convention — avoids conditional module output reference
var storageAccountName = toLower(take(replace(replace('st${namePrefix}gib', '-', ''), '_', ''), 24))
var resolvedScriptBaseUrl = usePrivateScriptStorage
  ? 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts'
  : scriptBaseUrl

// ── Image templates (one per enabled OS) ─────────────────────────────────────

module imageTemplates 'modules/imageTemplate.bicep' = [for config in enabledImageConfigs: {
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
    scriptBaseUrl: resolvedScriptBaseUrl
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
  dependsOn: [aibContributorRa]
}]

var enabledTemplateNames = [for config in enabledImageConfigs: 'aib-${namePrefix}-${config.name}']

// ── Logic App (schedule + manual trigger) ─────────────────────────────────────

module logicApp '../shared/modules/logicapp.bicep' = {
  name: 'logicapp'
  params: {
    location: location
    namePrefix: namePrefix
    logicAppIdentityId: identity.outputs.logicAppIdentityId
    imageTemplateNames: enabledTemplateNames
    buildScheduleDayOfMonth: buildScheduleDayOfMonth
    buildScheduleHour: buildScheduleHour
    subscriptionId: subscription().subscriptionId
    resourceGroupName: resourceGroup().name
    tags: tags
  }
  dependsOn: [imageTemplates, laContributorRa]
}

// ── Optional: private script storage ─────────────────────────────────────────

module storage '../shared/modules/storage.bicep' = if (usePrivateScriptStorage) {
  name: 'storage'
  params: {
    location: location
    namePrefix: namePrefix
    aibIdentityPrincipalId: identity.outputs.aibIdentityPrincipalId
    tags: tags
  }
}

// ── Optional: monitoring ──────────────────────────────────────────────────────

module monitoring '../shared/modules/monitoring.bicep' = if (enableLogAnalytics || !empty(notificationEmail)) {
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
output deployedImageTemplates array = enabledTemplateNames
@description('POST to this URL to manually trigger a build cycle for all image templates.')
output manualTriggerUrl string = logicApp.outputs.runnerTriggerUrl
output aibIdentityId string = identity.outputs.aibIdentityId
