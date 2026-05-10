// modules/openai-account/main.bicep
metadata description = 'Azure OpenAI account (Cognitive Services kind=OpenAI).'

param name string
param location string
param tags object

@description('Required. Custom subdomain for the account; must be globally unique.')
param customSubdomain string

@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

param disableLocalAuth bool = true

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  identity: { type: 'SystemAssigned' }
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: customSubdomain
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
    }
  }
}

// NOTE: never output listKeys(); endpoint and ID only.
output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output principalId string = account.identity.principalId
