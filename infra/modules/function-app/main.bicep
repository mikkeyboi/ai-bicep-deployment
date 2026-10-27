// modules/function-app/main.bicep
metadata description = 'Function App on the Flex Consumption plan, with a system-assigned identity and keyless deployment storage.'

// Why Flex Consumption and not the classic Y1 dynamic plan:
// Linux Consumption reaches end of life on 30 September 2028 and stops being
// supported. Flex is also a better fit for this workload independently of the
// deadline -- per-instance concurrency control and always-ready instances
// address the cold-start behaviour a timer-driven agent loop is sensitive to.
//
// Flex is NOT an in-place upgrade from Y1. The plan tier cannot be changed on
// an existing app, so migration is a recreate: new plan, new app, re-grant of
// every role the app's managed identity held. That is a deliberate, visible
// operation and the reason this module exists rather than a parameter tweak.

param name string
param planName string
param location string
param tags object

@description('Storage account hosting the deployment container AND the runtime\'s own state. Referenced by resource id so the module can grant the app identity access without ever reading a key.')
param storageAccountName string

@description('Blob container holding the deployment package. Flex mounts this rather than using the legacy WEBSITE_RUN_FROM_PACKAGE app setting.')
param deploymentContainerName string = 'app-package'

@allowed(['python', 'node', 'dotnet-isolated', 'java', 'powershell'])
param runtimeName string = 'python'

@description('Runtime version. Python 3.12 is supported through October 2028; 3.11 lapses a year earlier, so a new app should not be born on it.')
param runtimeVersion string = '3.12'

@description('Per-instance memory in MB. Flex bills on actual usage, so this caps concurrency rather than reserving spend.')
@allowed([2048, 4096])
param instanceMemoryMB int = 2048

@description('Ceiling on scale-out. Bounds the blast radius of a runaway trigger, which matters when each invocation calls a metered model endpoint.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 40

@description('Non-secret app settings. Connection strings and keys must NOT be passed here -- the app authenticates with its managed identity.')
param appSettings object = {}

@description('Application Insights connection string, when telemetry is wired.')
param appInsightsConnectionString string = ''

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: sa
  name: 'default'
}

// The deployment container is part of the app's contract, so it is declared
// here rather than left for a deploy script to create imperatively.
resource deployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  // FC1/FlexConsumption is the Flex tier. Unlike Y1 this serverfarm is a real
  // resource that must be declared; the platform does not conjure one.
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux
  }
}

// Storage endpoints built from the account name rather than read off the
// resource. `appSettings` is materialised in a for-expression, which ARM must
// resolve at the start of the deployment, so referencing sa.properties there
// fails with BCP178. The suffix comes from the cloud environment, so this stays
// correct in sovereign clouds instead of hardcoding "core.windows.net".
var storageSuffix = environment().suffixes.storage

var baseSettings = union(
  appSettings,
  {
    // The Functions host itself needs a storage account for trigger state,
    // singleton leases, and the timer's schedule ledger. Without it the app
    // deploys, registers its functions, and then never fires -- which looks
    // like a broken trigger rather than missing configuration.
    //
    // Set as the identity-based triple (no connection string, no key), which
    // is why the app's identity needs the blob/queue/table data roles.
    'AzureWebJobsStorage__accountName': storageAccountName
    'AzureWebJobsStorage__blobServiceUri': 'https://${storageAccountName}.blob.${storageSuffix}'
    'AzureWebJobsStorage__queueServiceUri': 'https://${storageAccountName}.queue.${storageSuffix}'
    'AzureWebJobsStorage__tableServiceUri': 'https://${storageAccountName}.table.${storageSuffix}'
  },
  empty(appInsightsConnectionString)
    ? {}
    : { APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString }
)

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${sa.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            // SystemAssignedIdentity, not a storage key. Constitution rule:
            // no listKeys(), no connection strings in configuration.
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: runtimeName
        version: runtimeVersion
      }
    }
    siteConfig: {
      appSettings: [
        for setting in items(baseSettings): {
          name: setting.key
          value: setting.value
        }
      ]
    }
  }
  dependsOn: [
    deployContainer
  ]
}

output id string = app.id
output name string = app.name
output principalId string = app.identity.principalId
output defaultHostName string = app.properties.defaultHostName
output planId string = plan.id
