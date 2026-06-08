// modules/machine-learning/main.bicep
metadata description = 'Azure Machine Learning workspace (Microsoft.MachineLearningServices/workspaces, kind=Default) with attached compute instances and clusters. Reuses the shared Storage / Key Vault / App Insights; datastores are keyless (systemDatastoresAuthMode=identity) so the workspace MSI authenticates to storage via RBAC. Names are resolved by the caller (workload.bicep) per the naming-discipline rule — this module never constructs names.'

import { amlComputeScale } from '../../shared/types.bicep'

// Compute inputs arrive with their resource name already resolved by the
// caller (names come only from infra/shared/naming.bicep).
@description('Compute instances (single-user dev boxes) with resolved names.')
type resolvedComputeInstance = {
  name: string
  vmSize: string
  idleTimeBeforeShutdown: string?
}

@description('Compute clusters (AmlCompute, autoscaling) with resolved names.')
type resolvedComputeCluster = {
  name: string
  vmSize: string
  vmPriority: ('Dedicated' | 'LowPriority')?
  scale: amlComputeScale
}

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

param computeInstances resolvedComputeInstance[] = []
param computeClusters resolvedComputeCluster[] = []

// ----- Workspace -----
// kind defaults to a standard ("Default") training workspace — NOT a
// Foundry hub (those live on Microsoft.CognitiveServices, per Constitution
// IV). systemDatastoresAuthMode='identity' makes the system datastores
// keyless; the workspace MSI reads storage via RBAC (granted in workload).
// API: 2024-10-01-preview — systemDatastoresAuthMode is preview-only (not
// in the 2024-10-01 GA schema). Consistent with the repo's existing use of
// preview CognitiveServices APIs.

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
    systemDatastoresAuthMode: 'identity'
    publicNetworkAccess: publicNetworkAccess
  }
}

// ----- Compute instances (single-user managed dev boxes) -----

resource instances 'Microsoft.MachineLearningServices/workspaces/computes@2024-10-01-preview' = [for ci in computeInstances: {
  parent: ws
  name: ci.name
  location: location
  tags: tags
  properties: {
    computeType: 'ComputeInstance'
    computeLocation: location
    description: 'AIO ${ci.name} compute instance'
    disableLocalAuth: true
    properties: union(
      {
        vmSize: ci.vmSize
        applicationSharingPolicy: 'Personal'
      },
      (ci.?idleTimeBeforeShutdown == null)
        ? {}
        : { idleTimeBeforeShutdown: ci.?idleTimeBeforeShutdown }
    )
  }
}]

// ----- Compute clusters (AmlCompute, autoscale; min 0 = scales to zero) -----

resource clusters 'Microsoft.MachineLearningServices/workspaces/computes@2024-10-01-preview' = [for cc in computeClusters: {
  parent: ws
  name: cc.name
  location: location
  tags: tags
  properties: {
    computeType: 'AmlCompute'
    computeLocation: location
    description: 'AIO ${cc.name} compute cluster'
    disableLocalAuth: true
    properties: {
      vmSize: cc.vmSize
      vmPriority: cc.?vmPriority ?? 'Dedicated'
      osType: 'Linux'
      enableNodePublicIp: true
      isolatedNetwork: false
      remoteLoginPortPublicAccess: 'Disabled'
      scaleSettings: {
        minNodeCount: cc.scale.minNodes
        maxNodeCount: cc.scale.maxNodes
        nodeIdleTimeBeforeScaleDown: cc.scale.nodeIdleTimeBeforeScaleDown
      }
    }
  }
}]

// NEVER output keys. IDs + endpoints + principalId only.
output id string = ws.id
output name string = ws.name
output principalId string = ws.identity.principalId
output computeInstanceNames array = [for ci in computeInstances: ci.name]
output computeClusterNames array = [for cc in computeClusters: cc.name]
