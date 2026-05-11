// modules/foundry-hub/main.bicep
metadata description = 'Azure AI Foundry hub (Microsoft.MachineLearningServices/workspaces, kind=Hub).'

param name string
param location string
param tags object

param keyVaultId string
param storageAccountId string
param appInsightsId string
param managedIdentityId string

@description('Optional. AI Search resource ID to associate with the hub.')
param aiSearchId string = ''

resource hub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'Hub'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: name
    primaryUserAssignedIdentity: managedIdentityId
    keyVault: keyVaultId
    storageAccount: storageAccountId
    applicationInsights: appInsightsId
    publicNetworkAccess: 'Enabled'
    hbiWorkspace: false
    v1LegacyMode: false
  }
}

output id string = hub.id
output name string = hub.name
@description('Hub system-assigned principalId. Empty when the hub only uses user-assigned identities (current default).')
output principalId string = contains(hub.identity, 'principalId') ? hub.identity.principalId : ''
@description('Echoed for downstream wiring; not used by the hub itself.')
output aiSearchId string = aiSearchId
