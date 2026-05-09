@description('Azure region.')
param location string

@description('CAF name prefix.')
param namePrefix string

@description('Email address for build notifications. Leave empty to skip action group + alerts.')
param notificationEmail string = ''

param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${namePrefix}-gib'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(notificationEmail)) {
  name: 'ag-${namePrefix}-gib'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'GoldImg'
    enabled: true
    emailReceivers: [
      {
        name: 'Primary'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Alert on AIB build failure
resource aibFailureAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (!empty(notificationEmail)) {
  name: 'alert-${namePrefix}-aib-failure'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'Administrative' }
        { field: 'resourceType', equals: 'microsoft.virtualmachineimages/imagetemplates' }
        { field: 'status', equals: 'Failed' }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
          webhookProperties: {}
        }
      ]
    }
    description: 'Fires when an Azure Image Builder run fails.'
  }
}

// Alert on AIB build success
resource aibSuccessAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (!empty(notificationEmail)) {
  name: 'alert-${namePrefix}-aib-success'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'Administrative' }
        { field: 'resourceType', equals: 'microsoft.virtualmachineimages/imagetemplates' }
        {
          field: 'operationName'
          equals: 'Microsoft.VirtualMachineImages/imageTemplates/run/action'
        }
        { field: 'status', equals: 'Succeeded' }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
          webhookProperties: {}
        }
      ]
    }
    description: 'Fires when an Azure Image Builder run succeeds.'
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
