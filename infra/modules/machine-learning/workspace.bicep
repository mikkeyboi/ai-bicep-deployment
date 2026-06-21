// modules/machine-learning/workspace.bicep
metadata description = 'Azure Machine Learning workspace (Microsoft.MachineLearningServices/workspaces, kind=Default). Reuses the shared Storage / Key Vault / App Insights; datastores are keyless (systemDatastoresAuthMode=identity) so the workspace MSI authenticates to storage via RBAC. Compute is a SEPARATE module (compute.bicep) that must be deployed AFTER the workspace MSI gets its storage roles — otherwise a ComputeInstance fails to mount workspacefilestore at create time. Names are resolved by the caller (workload.bicep).'

param name string
param location string
param tags object

@description('Optional human-friendly workspace name (no PII — public repo).')
param friendlyName string = ''

@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Resource IDs of the shared dependencies the workspace binds to.')
param storageAccountId string
param keyVaultId string
param appInsightsId string

@description('Optional resource ID of an existing Container Registry to keep attached. AzureML auto-creates and attaches an ACR the first time a job builds an environment image; once attached it CANNOT be detached ("Detaching Container Registry with workspace is not supported"), so a redeploy of a workspace declared without one fails. Pass the auto-created ACR NAME via containerRegistryName (the id is composed here so the paramfile never carries the subscription GUID). Empty = let AzureML manage it (valid only before the first image build).')
param containerRegistryName string = ''

// kind defaults to a standard ("Default") training workspace — NOT a
// Foundry hub (those live on Microsoft.CognitiveServices, per Constitution
// IV). systemDatastoresAuthMode='identity' makes the system datastores
// keyless; the workspace MSI reads storage via RBAC (granted in workload).
// API: 2024-10-01-preview — systemDatastoresAuthMode is preview-only (not
// in the 2024-10-01 GA schema). Consistent with the repo's existing use of
// preview CognitiveServices APIs.

// Compose the ACR id from its name so the subscription GUID is never written
// into a tracked paramfile (Constitution II): resourceId() resolves against
// the deploying subscription + this resource group at deploy time.
var containerRegistryId = empty(containerRegistryName)
  ? null
  : resourceId('Microsoft.ContainerRegistry/registries', containerRegistryName)

resource ws 'Microsoft.MachineLearningServices/workspaces@2024-10-01-preview' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: empty(friendlyName) ? null : friendlyName
    storageAccount: storageAccountId
    keyVault: keyVaultId
    applicationInsights: appInsightsId
    containerRegistry: containerRegistryId
    systemDatastoresAuthMode: 'identity'
    publicNetworkAccess: publicNetworkAccess
  }
}

// NEVER output keys. IDs + principalId only.
output id string = ws.id
output name string = ws.name
output principalId string = ws.identity.principalId
