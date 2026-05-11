// modules/foundry-connection/main.bicep
metadata description = 'Connection from a Foundry hub to a Cognitive Services account (AzureOpenAI), AAD-only. AIServices category was removed in v1.1.0 (Constitution VIII).'

import { connectionSpec } from '../../shared/types.bicep'

param hubName string
param connection connectionSpec

resource hub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' existing = {
  name: hubName
}

resource conn 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: hub
  name: connection.name
  properties: {
    category: connection.category
    target: reference(connection.targetResourceId, '2024-10-01').endpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ResourceId: connection.targetResourceId
      ApiType: 'Azure'
    }
  }
}

output id string = conn.id
output name string = conn.name
