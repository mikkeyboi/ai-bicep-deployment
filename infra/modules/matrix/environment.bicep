// modules/matrix/environment.bicep
// ACA Managed Environment (internal load balancer) with Log Analytics
// integration and one storage definition bound to an Azure Files share
// used by continuwuity.

metadata description = 'Container Apps Environment (internal LB) + storage link to Azure Files share for continuwuity.'

param name string
param location string
param tags object
param logAnalyticsWorkspaceId string

@description('Existing storage account hosting the Azure Files share.')
param storageAccountName string

@description('File share name (already created by file-share.bicep).')
param fileShareName string

@description('Logical name used by container apps to reference this storage.')
param storageMountName string = 'continuwuity-data'

// Pull workspace customerId + key from the existing LAW resource.
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
}

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
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
    vnetConfiguration: {
      internal: true
    }
    zoneRedundant: false
  }
}

// NOTE: This invokes listKeys() on the storage account inline — required
// by ACA's storage definition API and never exposed as an output
// (Constitution II).
resource envStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: env
  name: storageMountName
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: sa.listKeys().keys[0].value
      shareName: fileShareName
      accessMode: 'ReadWrite'
    }
  }
}

output id string = env.id
output name string = env.name
output defaultDomain string = env.properties.defaultDomain
output storageName string = envStorage.name
