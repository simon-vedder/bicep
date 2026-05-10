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
@description('Build and maintain an Ubuntu 22.04 LTS golden image.')
param enableUbuntu2204 bool = true

@description('Build and maintain an Ubuntu 24.04 LTS golden image.')
param enableUbuntu2404 bool = true

@description('Build and maintain a RHEL 8 golden image.')
param enableRhel8 bool = false

@description('Build and maintain a RHEL 9 golden image.')
param enableRhel9 bool = true

// Customization
@description('Apply CIS-aligned security hardening.')
param enableSecurityHardening bool = false

// Script source
@description('Base URL for shell customization scripts. Change only if using a fork or private storage.')
param scriptBaseUrl string = 'https://raw.githubusercontent.com/simon-vedder/bicep/add/goldenimagebuilder/automations/build-golden-image/linux/scripts'

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
    enableWindowsServer2022: false
    enableWindowsServer2025: false
    enableWindows11MultiSession: false
    enableWindows11SingleSession: false
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

var imageConfigs = [
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

var enabledImageConfigs = filter(imageConfigs, config => config.enabled)

var storageAccountName = toLower(take('stgib${replace(replace(namePrefix, '-', ''), '_', '')}', 24))
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
    aibIdentityId: identity.outputs.aibIdentityId
    galleryName: gallery.outputs.galleryName
    scriptBaseUrl: resolvedScriptBaseUrl
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

var linuxScriptFileNames = ['linux-updates.sh', 'security-hardening.sh']

module storage '../shared/modules/storage.bicep' = if (usePrivateScriptStorage) {
  name: 'storage'
  params: {
    location: location
    namePrefix: namePrefix
    aibIdentityPrincipalId: identity.outputs.aibIdentityPrincipalId
    scriptSourceBaseUrl: scriptBaseUrl
    scriptFileNames: linuxScriptFileNames
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
