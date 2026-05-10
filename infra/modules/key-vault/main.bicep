// modules/key-vault/main.bicep
metadata description = 'Azure Key Vault, RBAC mode, soft-delete on, purge protection per env.'

param name string
param location string
param tags object

@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

param enablePurgeProtection bool = false

@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 30

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// NOTE (Constitution II + IV): we deliberately do NOT output any keys.
output id string = kv.id
output name string = kv.name
output uri string = kv.properties.vaultUri
