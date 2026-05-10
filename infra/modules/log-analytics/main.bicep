// modules/log-analytics/main.bicep
metadata description = 'Log Analytics workspace for centralized diagnostics.'

param name string
param location string
param tags object

@minValue(7)
@maxValue(730)
param retentionInDays int = 30

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output id string = law.id
output name string = law.name
output customerId string = law.properties.customerId
