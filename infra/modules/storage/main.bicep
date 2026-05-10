// modules/storage/main.bicep
metadata description = 'Storage account: StorageV2, LRS, Entra-only by default.'

param name string
param location string
param tags object

@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS', 'Standard_RAGRS'])
param skuName string = 'Standard_LRS'

@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

param allowSharedKeyAccess bool = false

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: skuName }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: allowSharedKeyAccess
    allowCrossTenantReplication: false
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
      bypass: 'AzureServices,Logging,Metrics'
    }
    encryption: {
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false
    }
  }
}

// NOTE (Constitution II + IV): no listKeys() output.
output id string = sa.id
output name string = sa.name
output primaryBlobEndpoint string = sa.properties.primaryEndpoints.blob
