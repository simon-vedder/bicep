@description('Azure region.')
param location string

@description('CAF name prefix.')
param namePrefix string

@description('Resource ID of the Logic App user-assigned managed identity.')
param logicAppIdentityId string

@description('Names of the AIB image templates to trigger on each run.')
param imageTemplateNames array

@description('Day of month for the scheduled build (1-28).')
@minValue(1)
@maxValue(28)
param buildScheduleDayOfMonth int = 15

@description('Hour (UTC) for the scheduled build (0-23).')
@minValue(0)
@maxValue(23)
param buildScheduleHour int = 2

@description('Azure subscription ID where AIB templates live.')
param subscriptionId string

@description('Resource group name where AIB templates live.')
param resourceGroupName string

param tags object = {}

// ── Runner Logic App ─────────────────────────────────────────────────────────
// One HTTP action per template — baked in at deploy time via toObject().
// No Logic App expressions needed — avoids single-quote escaping issues in Bicep.

var armBaseUrl = environment().resourceManager  // https://management.azure.com/ (cloud-portable)

var runnerActions = toObject(
  imageTemplateNames,
  // Action names: hyphens → underscores (Logic App action name constraint)
  templateName => 'Run_${replace(templateName, '-', '_')}',
  templateName => {
    type: 'Http'
    runAfter: {}
    inputs: {
      method: 'POST'
      uri: '${armBaseUrl}subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.VirtualMachineImages/imageTemplates/${templateName}/run?api-version=2024-02-01'
      authentication: {
        type: 'ManagedServiceIdentity'
        identity: logicAppIdentityId
        audience: armBaseUrl
      }
    }
  }
)

var runnerDefinition = {
  '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
  contentVersion: '1.0.0.0'
  parameters: {}
  triggers: {
    manual: {
      type: 'Request'
      kind: 'Http'
      inputs: { schema: {} }
    }
  }
  actions: runnerActions
}

resource runnerLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-${namePrefix}-runner'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logicAppIdentityId}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: runnerDefinition
  }
}

// SAS-signed trigger URL — implicit dependency on runnerLogicApp via resource ID reference
var runnerTriggerUrl = listCallbackUrl('${runnerLogicApp.id}/triggers/manual', '2019-05-01').value

// ── Scheduler Logic App ──────────────────────────────────────────────────────
// Recurrence trigger calls the runner trigger URL directly (baked in at deploy time).

var schedulerDefinition = {
  '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
  contentVersion: '1.0.0.0'
  parameters: {}
  triggers: {
    Monthly_Build_Schedule: {
      type: 'Recurrence'
      recurrence: {
        frequency: 'Month'
        interval: 1
        timeZone: 'UTC'
        schedule: {
          monthDays: [buildScheduleDayOfMonth]
          hours: ['${buildScheduleHour}']
          minutes: [0]
        }
      }
    }
  }
  actions: {
    Trigger_Runner: {
      type: 'Http'
      runAfter: {}
      inputs: {
        method: 'POST'
        uri: runnerTriggerUrl
      }
    }
  }
}

resource schedulerLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'la-${namePrefix}-scheduler'
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: schedulerDefinition
  }
}

output runnerLogicAppId string = runnerLogicApp.id
output runnerLogicAppName string = runnerLogicApp.name
output schedulerLogicAppName string = schedulerLogicApp.name
output runnerTriggerUrl string = runnerTriggerUrl
