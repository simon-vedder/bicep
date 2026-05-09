@description('Azure region.')
param location string

@description('CAF name prefix.')
param namePrefix string

@description('Principal ID of the AIB UAMI — granted Storage Blob Data Reader.')
param aibIdentityPrincipalId string

param tags object = {}

// Storage account name: 3-24 chars, lowercase alphanumeric only
// Fixed prefix 'stgib' (5 chars) guarantees Bicep type-checker sees min length >= 3
var storageAccountName = toLower(take('stgib${replace(replace(namePrefix, '-', ''), '_', '')}', 24))

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource scriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'scripts'
  properties: {
    publicAccess: 'None'
  }
}

// AIB UAMI needs read access to pull scripts during build
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource aibStorageRa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aibIdentityPrincipalId, storageBlobDataReaderRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalId: aibIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output scriptsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}scripts'
