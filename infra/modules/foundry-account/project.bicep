// modules/foundry-account/project.bicep
metadata description = 'AI Foundry project (Microsoft.CognitiveServices/accounts/projects) — child of an AIServices account.'

param accountName string
param name string
param location string
param tags object

@description('Optional human-friendly display name. Defaults to the resource name.')
param displayName string = name

@description('Optional description shown in the Foundry portal.')
param projectDescription string = 'AI Foundry project'

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    description: projectDescription
    displayName: displayName
  }
}

output id string = project.id
output name string = project.name
