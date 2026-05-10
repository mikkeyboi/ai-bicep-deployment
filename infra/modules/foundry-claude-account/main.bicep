// modules/foundry-claude-account/main.bicep
metadata description = 'Cognitive Services account (kind=AIServices) used to host Anthropic Claude model deployments through Microsoft Foundry.'

param name string
param location string
param tags object

@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

param disableLocalAuth bool = true

@description('Required. Custom subdomain (globally unique).')
param customSubdomain string

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
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

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output principalId string = account.identity.principalId
