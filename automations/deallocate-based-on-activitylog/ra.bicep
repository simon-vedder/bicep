targetScope = 'subscription'

param logicAppIdentity string

// role assignment for managed identity
// Desktop Virtualization Power On Off Contributor: read, start, power off and deallocate a VM,
// and nothing else. Virtual Machine Contributor could also install extensions and run commands,
// which this workflow never needs.
var powerRoleId = '40c5ff49-9181-41f8-ae61-143b0e78555e'

resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
    scope: subscription()
    name: powerRoleId
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, powerRoleId)
  scope: subscription()
  properties: {
    roleDefinitionId: roleDefinition.id
    principalId: logicAppIdentity
    principalType: 'ServicePrincipal'
  }
}
