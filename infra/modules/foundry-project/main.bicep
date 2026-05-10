// modules/foundry-project/main.bicep
metadata description = 'Foundry project (kind=Project) attached to a hub.'

param name string
param location string
param tags object

@description('Required. Hub workspace resource ID.')
param hubId string

resource project 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'Project'
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: name
    hubResourceId: hubId
    publicNetworkAccess: 'Enabled'
    v1LegacyMode: false
  }
}

output id string = project.id
output name string = project.name
output discoveryUrl string = project.properties.discoveryUrl
