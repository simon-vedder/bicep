@description('Azure region.')
param location string

@description('CAF name prefix.')
param namePrefix string

@description('Short OS identifier — used in resource names.')
param imageName string

param imagePublisher string
param imageOffer string
param imageSku string

@description('Resource ID of the AIB user-assigned managed identity.')
param aibIdentityId string

@description('Name of the Azure Compute Gallery.')
param galleryName string

@description('Base URL for shell customization scripts.')
param scriptBaseUrl string

param enableSecurityHardening bool = false

param useVNetInjection bool = false
param vnetResourceGroupName string = ''
param vnetName string = ''
param subnetName string = ''

param replicationRegions array = []

param tags object = {}

var imageDefinitionName = 'imgdef-${namePrefix}-${imageName}'

var baseCustomizers = [
  {
    type: 'Shell'
    name: 'LinuxUpdates'
    scriptUri: '${scriptBaseUrl}/linux-updates.sh'
  }
]

var hardeningCustomizers = enableSecurityHardening ? [
  {
    type: 'Shell'
    name: 'SecurityHardening'
    scriptUri: '${scriptBaseUrl}/security-hardening.sh'
  }
] : []

var allCustomizers = concat(baseCustomizers, hardeningCustomizers)

var distributeBase = [
  {
    type: 'SharedImage'
    galleryImageId: resourceId('Microsoft.Compute/galleries/images', galleryName, imageDefinitionName)
    runOutputName: 'run-${imageName}'
    replicationRegions: concat([location], replicationRegions)
    storageAccountType: 'Standard_LRS'
  }
]

var vmProfileBase = {
  vmSize: 'Standard_D4s_v3'
  osDiskSizeGB: 86
}

var vnetConfig = useVNetInjection ? {
  vnetConfig: {
    subnetId: resourceId(vnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
  }
} : {}

resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2024-02-01' = {
  name: 'aib-${namePrefix}-${imageName}'
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
    source: {
      type: 'PlatformImage'
      publisher: imagePublisher
      offer: imageOffer
      sku: imageSku
      version: 'latest'
    }
    customize: allCustomizers
    distribute: distributeBase
    vmProfile: union(vmProfileBase, vnetConfig)
  }
}

output imageTemplateId string = imageTemplate.id
output imageTemplateName string = imageTemplate.name
