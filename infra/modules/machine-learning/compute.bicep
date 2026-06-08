// modules/machine-learning/compute.bicep
metadata description = 'AML compute instances + clusters attached to an existing workspace. Deployed AFTER the workspace MSI holds Storage Blob/File Data roles (the caller wires dependsOn on those role assignments) because a ComputeInstance mounts workspacefilestore via the workspace identity DURING its own provisioning — if the file role is not yet present the instance fails with StorageMountError. The cluster (min 0 nodes) does not mount at create, but it shares the ordering for simplicity. Names are resolved by the caller (workload.bicep).'

import { amlComputeScale } from '../../shared/types.bicep'

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

@description('Name of the existing workspace to attach compute to.')
param workspaceName string
param location string
param tags object

param computeInstances resolvedComputeInstance[] = []
param computeClusters resolvedComputeCluster[] = []

resource ws 'Microsoft.MachineLearningServices/workspaces@2024-10-01-preview' existing = {
  name: workspaceName
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

output computeInstanceNames array = [for ci in computeInstances: ci.name]
output computeClusterNames array = [for cc in computeClusters: cc.name]
