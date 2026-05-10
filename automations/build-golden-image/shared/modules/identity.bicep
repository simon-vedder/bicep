@description('Azure region for the managed identities.')
param location string

@description('CAF name prefix. Drives resource names.')
param namePrefix string

param tags object = {}

resource aibIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-${namePrefix}-aib'
  location: location
  tags: tags
}

resource logicAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-${namePrefix}-la'
  location: location
  tags: tags
}

output aibIdentityId string = aibIdentity.id
output aibIdentityPrincipalId string = aibIdentity.properties.principalId
output aibIdentityClientId string = aibIdentity.properties.clientId
output logicAppIdentityId string = logicAppIdentity.id
output logicAppIdentityPrincipalId string = logicAppIdentity.properties.principalId
output logicAppIdentityClientId string = logicAppIdentity.properties.clientId
