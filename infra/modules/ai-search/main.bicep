// modules/ai-search/main.bicep
metadata description = 'Azure AI Search service for Foundry RAG scenarios.'

param name string
param location string
param tags object

@allowed(['free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param skuName string = 'basic'

@allowed(['enabled', 'disabled'])
param publicNetworkAccess string = 'enabled'

resource srch 'Microsoft.Search/searchServices@2024-03-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: skuName }
  identity: { type: 'SystemAssigned' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: publicNetworkAccess
    semanticSearch: 'free'
    authOptions: {
      aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge' }
    }
    disableLocalAuth: false
  }
}

output id string = srch.id
output name string = srch.name
output endpoint string = 'https://${srch.name}.search.windows.net'
output principalId string = srch.identity.principalId
