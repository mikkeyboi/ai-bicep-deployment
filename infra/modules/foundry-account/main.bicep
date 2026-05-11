// modules/foundry-account/main.bicep
metadata description = 'AI Foundry account (Microsoft.CognitiveServices/accounts kind=AIServices) with optional model deployments. Replaces the legacy hub workspace + sidecar OpenAI account.'

import { modelDeployment } from '../../shared/types.bicep'

param name string
param location string
param tags object

@description('Required. Globally-unique custom subdomain for the account.')
param customSubdomain string

@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

param disableLocalAuth bool = true

@description('Optional. Model deployments to attach directly to this Foundry account.')
param deployments modelDeployment[] = []

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  identity: { type: 'SystemAssigned' }
  sku: { name: 'S0' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: customSubdomain
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
    }
  }
}

@batchSize(1)
resource modelDeployments 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [for d in deployments: {
  parent: account
  name: d.name
  sku: {
    name: d.sku.name
    capacity: d.sku.capacity
  }
  properties: {
    model: {
      format: d.model.format
      name: d.model.name
      version: d.model.version == 'latest' ? null : d.model.version
    }
    raiPolicyName: d.?raiPolicyName
    versionUpgradeOption: d.?versionUpgradeOption ?? 'OnceNewDefaultVersionAvailable'
  }
}]

// NEVER output listKeys(); endpoint + ID only.
output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output principalId string = account.identity.principalId
output deploymentNames array = [for d in deployments: d.name]
