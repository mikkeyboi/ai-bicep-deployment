// modules/azure-mcp/environment.bicep
// Public (external-ingress) Container Apps Environment for the Azure MCP
// connector. Separate from the Matrix environment, which is internal-only
// and VNet-bound: Claude reaches connectors from Anthropic's egress range,
// and the user's browser must reach the OAuth endpoints, so this one needs
// a public FQDN. Consumption profile only, so idle cost tracks replicas.

metadata description = 'External Container Apps Environment (Consumption workload profile) with Log Analytics.'

param name string
param location string
param tags object
param logAnalyticsWorkspaceId string

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

output id string = env.id
output name string = env.name
output defaultDomain string = env.properties.defaultDomain
