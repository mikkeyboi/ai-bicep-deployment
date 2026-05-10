// modules/openai-deployment/main.bicep
metadata description = 'A single model deployment under an OpenAI account.'

import { modelDeployment } from '../../shared/types.bicep'

param accountName string
param deployment modelDeployment

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource dep 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deployment.name
  sku: {
    name: deployment.sku.name
    capacity: deployment.sku.capacity
  }
  properties: {
    model: {
      format: deployment.model.format
      name: deployment.model.name
      version: deployment.model.version == 'latest' ? null : deployment.model.version
    }
    raiPolicyName: deployment.?raiPolicyName ?? 'Microsoft.Default'
    versionUpgradeOption: deployment.?versionUpgradeOption ?? 'OnceNewDefaultVersionAvailable'
  }
}

output id string = dep.id
output name string = dep.name
