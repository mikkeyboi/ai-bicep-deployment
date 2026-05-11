// infra/main.bicep
// Subscription-scope entry point. Creates the resource group and
// invokes the workload module. Validates region/model availability
// before any resource is created.

targetScope = 'subscription'

import { environmentConfig } from 'shared/types.bicep'
import { rg } from 'shared/naming.bicep'
import { standardTags } from 'shared/tags.bicep'
import { isSupported, missingMessage } from 'shared/region-capabilities.bicep'

@description('Required. Typed environment configuration; comes from main.<env>.bicepparam.')
param config environmentConfig

@description('Stable timestamp threaded into tags so all child resources see the same value.')
param deployedAt string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ---- Region/model capability gate ----
// Constitution v1.2.0: model deployments live on the unified Foundry
// account (Microsoft.CognitiveServices kind=AIServices). Same first-
// party `format=OpenAI` model surface as before.

var foundryModels = [for d in config.foundry.deployments: { format: d.model.format, name: d.model.name }]
var requestedModels = config.foundry.enabled ? foundryModels : []

var unsupportedModels = filter(requestedModels, m => !isSupported(config.location, m.format, m.name))

var capabilityOk = empty(unsupportedModels)
var firstViolation = capabilityOk ? { format: 'OK', name: 'OK' } : unsupportedModels[0]
var capabilityMessage = capabilityOk ? 'OK' : missingMessage(config.location, firstViolation.format, firstViolation.name)

resource regionCapabilityFail 'Microsoft.Resources/deployments@2024-03-01' = if (!capabilityOk) {
  name: 'REGION-CAPABILITY-FAIL'
  location: config.location
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: [
        {
          type: 'Microsoft.Resources/deployments'
          apiVersion: '2024-03-01'
          name: 'see-deployment-name-and-output-message'
          properties: {
            mode: 'Incremental'
            template: {
              '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
              contentVersion: '1.0.0.0'
              resources: []
            }
          }
        }
      ]
      outputs: {
        message: { type: 'string', value: '[parameters(\'msg\')]' }
      }
      parameters: {
        msg: { type: 'string' }
      }
    }
    parameters: {
      msg: { value: capabilityMessage }
    }
  }
}

// ---- Resource group ----

var rgName = rg(config.workloadName, config.environment, config.location, config.?instance ?? '')
var workloadTags = standardTags(config.environment, config.workloadName, config.owner, config.costCenter, deployedAt)

resource resGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: config.location
  tags: workloadTags
}

// ---- Workload at RG scope ----

module workload 'workload.bicep' = {
  name: 'workload-${config.environment}'
  scope: resGroup
  params: {
    config: config
    tags: workloadTags
    uniqueSeed: '${subscription().subscriptionId}-${rgName}'
  }
}

// ---- Outputs ----

output resourceGroupName string = resGroup.name
output regionCapabilityMessage string = capabilityMessage
output requestedModelCount int = length(requestedModels)
output workloadOutputs object = {
  foundryAccountId: workload.outputs.foundryAccountId
  foundryAccountEndpoint: workload.outputs.foundryAccountEndpoint
  foundryProjectId: workload.outputs.foundryProjectId
  foundryDeploymentNames: workload.outputs.foundryDeploymentNames
  keyVaultId: workload.outputs.keyVaultId
  keyVaultUri: workload.outputs.keyVaultUri
  storageAccountId: workload.outputs.storageAccountId
  managedIdentityId: workload.outputs.managedIdentityId
  managedIdentityPrincipalId: workload.outputs.managedIdentityPrincipalId
  managedIdentityClientId: workload.outputs.managedIdentityClientId
  logAnalyticsWorkspaceId: workload.outputs.logAnalyticsWorkspaceId
  appInsightsId: workload.outputs.appInsightsId
  aiSearchId: workload.outputs.aiSearchId
}
