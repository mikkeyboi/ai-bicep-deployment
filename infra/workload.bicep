// infra/workload.bicep
// Resource-group-scope orchestrator. Receives the typed config + tags
// from main.bicep and invokes every module per
// specs/002-new-foundry/contracts/modules.contract.md.

targetScope = 'resourceGroup'

import { environmentConfig } from 'shared/types.bicep'
import {
  law as nameLaw
  ai as nameAi
  mi as nameMi
  kv as nameKv
  storage as nameStorage
  foundry as nameFoundry
  project as nameProject
  search as nameSearch
  cae as nameCae
  ca as nameCa
  vnet as nameVnet
  mlWorkspace as nameMlw
  mlComputeInstance as nameMlCi
  mlComputeCluster as nameMlCc
} from 'shared/naming.bicep'

param config environmentConfig
param tags object
param uniqueSeed string

// ----- Names -----
var instance = config.?instance ?? ''

var laName    = nameLaw    (config.workloadName, config.environment, config.location, instance)
var aiName    = nameAi     (config.workloadName, config.environment, config.location, instance)
var miName    = nameMi     (config.workloadName, config.environment, config.location, instance)
var kvName    = nameKv     (config.workloadName, config.environment, config.location, instance, uniqueSeed)
var stName    = nameStorage(config.workloadName, config.environment, config.location, instance, uniqueSeed)
var aifName   = nameFoundry(config.workloadName, config.environment, config.location, instance, uniqueSeed)
var projName  = nameProject(config.workloadName, config.environment, config.location, instance)
var srchName  = nameSearch (config.workloadName, config.environment, config.location, instance, uniqueSeed)

var pnaResource = config.enablePublicNetworkAccess ? 'Enabled' : 'Disabled'
var enableSearch = config.?enableAiSearch ?? false
var enableMatrix = config.?enableMatrix ?? false
var caeName = nameCae(config.workloadName, config.environment, config.location, instance)
var caName  = nameCa (config.workloadName, config.environment, config.location, instance)
var vnetName = nameVnet(config.workloadName, config.environment, config.location, instance)

// Secondary Foundry (feature 004): an optional second AIServices account
// in a different region, for models only available outside the primary
// location (e.g. eastus-only image models gpt-image-2 / MAI-Image-2.5).
// Its name embeds the secondary region short-code, so it never collides
// with the primary `aif-…-eus2-…` account.
var enableSecondaryFoundry = config.?secondaryFoundry.?enabled ?? false
var secondaryLocation = config.?secondaryFoundry.?location ?? config.location
var aif2Name  = nameFoundry(config.workloadName, config.environment, secondaryLocation, instance, uniqueSeed)
var proj2Name = nameProject(config.workloadName, config.environment, secondaryLocation, instance)

// Azure ML (feature 007): optional workspace + attached compute. The
// processor class ('cpu'/'gpu') goes in the name's instance slot, so the
// CPU targets keep their names when a GPU entry is appended later. Names
// are resolved HERE (naming-discipline rule) and passed to the module as
// already-named records.
var enableMl = config.?machineLearning.?enabled ?? false
var mlwName = nameMlw(config.workloadName, config.environment, config.location, instance)
var mlInstances = enableMl ? map(config.machineLearning!.computeInstances, ci => {
  name: nameMlCi(config.workloadName, config.environment, config.location, ci.processor)
  vmSize: ci.vmSize
  idleTimeBeforeShutdown: ci.?idleTimeBeforeShutdown
}) : []
var mlClusters = enableMl ? map(config.machineLearning!.computeClusters, cc => {
  name: nameMlCc(config.workloadName, config.environment, config.location, cc.processor)
  vmSize: cc.vmSize
  vmPriority: cc.?vmPriority
  scale: cc.scale
}) : []

// ----- Foundational -----

module law 'modules/log-analytics/main.bicep' = {
  name: 'law'
  params: {
    name: laName
    location: config.location
    tags: tags
    retentionInDays: config.diagnosticsRetentionDays
  }
}

module appi 'modules/app-insights/main.bicep' = {
  name: 'appi'
  params: {
    name: aiName
    location: config.location
    tags: tags
    workspaceResourceId: law.outputs.id
  }
}

module mi 'modules/managed-identity/main.bicep' = {
  name: 'mi'
  params: {
    name: miName
    location: config.location
    tags: tags
  }
}

module kv 'modules/key-vault/main.bicep' = {
  name: 'kv'
  params: {
    name: kvName
    location: config.location
    tags: tags
    publicNetworkAccess: pnaResource
    enablePurgeProtection: config.enablePurgeProtection
  }
}

module sa 'modules/storage/main.bicep' = {
  name: 'st'
  params: {
    name: stName
    location: config.location
    tags: tags
    publicNetworkAccess: pnaResource
    allowSharedKeyAccess: config.environment == 'prod' ? false : true
  }
}

module srch 'modules/ai-search/main.bicep' = if (enableSearch) {
  name: 'srch'
  params: {
    name: srchName
    location: config.location
    tags: tags
    skuName: 'basic'
    publicNetworkAccess: config.enablePublicNetworkAccess ? 'enabled' : 'disabled'
  }
}

// ----- Foundry account + child project + model deployments -----
//
// Constitution v1.2.0: AI Foundry uses the unified Foundry resource
// (Microsoft.CognitiveServices kind=AIServices). Models live on the
// Foundry account itself; the legacy hub workspace + sidecar OpenAI
// account from feature 001 are gone.

module foundry 'modules/foundry-account/main.bicep' = if (config.foundry.enabled) {
  name: 'aif'
  params: {
    name: aifName
    location: config.location
    tags: tags
    customSubdomain: aifName
    publicNetworkAccess: pnaResource
    disableLocalAuth: config.foundry.?disableLocalAuth ?? true
    deployments: config.foundry.deployments
  }
}

module foundryProj 'modules/foundry-account/project.bicep' = if (config.foundry.enabled) {
  name: 'aif-proj'
  params: {
    accountName: aifName
    name: projName
    location: config.location
    tags: tags
    displayName: projName
    projectDescription: '${config.workloadName} ${config.environment} Foundry project'
  }
  dependsOn: [ foundry ]
}

// ----- Secondary Foundry account + project (feature 004) -----
//
// Optional second AIServices account in `secondaryLocation` (e.g. eastus)
// hosting models not available in the primary region. Local auth (API
// keys) is re-enabled on THIS account only when the paramfile sets
// secondaryFoundry.disableLocalAuth=false; the primary account stays
// Entra-only. listKeys() is still never emitted — keys are read at
// runtime via `az cognitiveservices account keys list`.

module foundry2 'modules/foundry-account/main.bicep' = if (enableSecondaryFoundry) {
  name: 'aif2'
  params: {
    name: aif2Name
    location: secondaryLocation
    tags: tags
    customSubdomain: aif2Name
    publicNetworkAccess: pnaResource
    disableLocalAuth: config.?secondaryFoundry.?disableLocalAuth ?? true
    deployments: enableSecondaryFoundry ? config.secondaryFoundry!.deployments : []
  }
}

module foundry2Proj 'modules/foundry-account/project.bicep' = if (enableSecondaryFoundry) {
  name: 'aif2-proj'
  params: {
    accountName: aif2Name
    name: proj2Name
    location: secondaryLocation
    tags: tags
    displayName: proj2Name
    projectDescription: '${config.workloadName} ${config.environment} secondary Foundry project (${secondaryLocation})'
  }
  dependsOn: [ foundry2 ]
}

// ----- Azure Machine Learning workspace + compute (feature 007) -----
//
// Optional, additive training workspace (kind=Default — a real ML
// workspace, NOT a Foundry hub; Foundry stays on CognitiveServices per
// Constitution IV). Binds the shared storage / Key Vault / App Insights.
// Datastores are keyless (systemDatastoresAuthMode=identity); the
// workspace's OWN system-assigned MSI is granted storage + KV roles below.
// Compute names carry the processor class, so appending a processor='gpu'
// entry adds GPU capacity with no rename of the cpu targets.
//
// ORDERING (lesson from the first deploy): workspace -> RBAC grants ->
// compute. A ComputeInstance mounts workspacefilestore via the workspace
// MSI DURING its own provisioning, so the 'Storage File Data Privileged
// Contributor' grant MUST exist first or the instance fails with
// StorageMountError. The compute module (below the RBAC block) therefore
// dependsOn the ML role assignments.

module mlWs 'modules/machine-learning/workspace.bicep' = if (enableMl) {
  name: 'ml-ws'
  params: {
    name: mlwName
    location: config.location
    tags: tags
    friendlyName: config.?machineLearning.?friendlyName ?? ''
    publicNetworkAccess: pnaResource
    storageAccountId: sa.outputs.id
    keyVaultId: kv.outputs.id
    appInsightsId: appi.outputs.id
    containerRegistryName: config.?machineLearning.?containerRegistryName ?? ''
  }
}

// ----- RBAC: grant the workload MI least-privilege roles -----

var miPid = mi.outputs.principalId

module raFoundry 'modules/role-assignment/main.bicep' = if (config.foundry.enabled) {
  name: 'ra-mi-aif'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Cognitive Services User'
      scopeResourceId: foundry!.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> Foundry account inference'
    }
  }
}

// NOTE (feature 005): no separate role assignment for the secondary
// (eastus) Foundry account. The role-assignment module assigns at
// `scope: resourceGroup()` (scopeResourceId only feeds the deterministic
// name), so `raFoundry` above already grants the workload MI
// 'Cognitive Services User' across the whole RG — which covers the
// secondary account too. Adding a second assignment for the same
// (principal, role, RG-scope) tuple fails at deploy time with
// RoleAssignmentExists (Azure dedupes by scope+principal+role, not by
// name). See specs/005-fix-foundry2-rbac/.

module raKv 'modules/role-assignment/main.bicep' = {
  name: 'ra-mi-kv'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Key Vault Secrets User'
      scopeResourceId: kv.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> Key Vault secret reads'
    }
  }
}

module raSt 'modules/role-assignment/main.bicep' = {
  name: 'ra-mi-st'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      scopeResourceId: sa.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> Storage blob R/W'
    }
  }
}

module raSrch 'modules/role-assignment/main.bicep' = if (enableSearch) {
  name: 'ra-mi-srch'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Search Index Data Contributor'
      scopeResourceId: srch!.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> AI Search index R/W'
    }
  }
}

// ----- RBAC: the ML workspace's OWN system-assigned MSI (feature 007) -----
//
// Keyless datastores (systemDatastoresAuthMode=identity) require the
// workspace identity itself to reach the shared storage over Entra. This
// is a DIFFERENT principal from the workload MI above, so reusing the same
// role names does not collide (Azure dedupes by scope+principal+role).
// Blob = workspaceblobstore; File = workspacefilestore; KV Secrets Officer
// lets the workspace persist connection secrets it manages.

var mlPid = enableMl ? mlWs!.outputs.principalId : ''

module raMlBlob 'modules/role-assignment/main.bicep' = if (enableMl) {
  name: 'ra-ml-blob'
  params: {
    roleAssignment: {
      principalId: mlPid
      roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      scopeResourceId: sa.outputs.id
      principalType: 'ServicePrincipal'
      description: 'ML workspace MSI -> workspaceblobstore (keyless datastore)'
    }
  }
}

module raMlFile 'modules/role-assignment/main.bicep' = if (enableMl) {
  name: 'ra-ml-file'
  params: {
    roleAssignment: {
      principalId: mlPid
      roleDefinitionIdOrName: 'Storage File Data Privileged Contributor'
      scopeResourceId: sa.outputs.id
      principalType: 'ServicePrincipal'
      description: 'ML workspace MSI -> workspacefilestore (keyless datastore)'
    }
  }
}

module raMlKv 'modules/role-assignment/main.bicep' = if (enableMl) {
  name: 'ra-ml-kv'
  params: {
    roleAssignment: {
      principalId: mlPid
      roleDefinitionIdOrName: 'Key Vault Secrets Officer'
      scopeResourceId: kv.outputs.id
      principalType: 'ServicePrincipal'
      description: 'ML workspace MSI -> Key Vault connection secrets R/W'
    }
  }
}

// ----- ML compute (feature 007) — created AFTER the RBAC grants -----
//
// Must run after raMlBlob/raMlFile (and raMlKv) so the workspace MSI can
// mount workspacefilestore at ComputeInstance create time. Without this
// dependsOn the instance races the role assignment and fails with
// StorageMountError (observed on the first deploy).

module mlCompute 'modules/machine-learning/compute.bicep' = if (enableMl) {
  name: 'ml-compute'
  params: {
    workspaceName: mlwName
    location: config.location
    tags: tags
    computeInstances: mlInstances
    computeClusters: mlClusters
  }
  dependsOn: [ mlWs, raMlBlob, raMlFile, raMlKv ]
}

// ----- ML compute identity -> storage (keyless datastore reads at job time) -----
//
// An AmlCompute job that reads a keyless (identity-based) datastore - e.g. the
// mechinterp trials_datalake - authenticates as the CLUSTER's own MSI, NOT the
// workspace MSI. Without this grant the run fails with "Identity of the
// specified managed compute ... is not found". One grant per cluster, created
// AFTER ml-compute so the principalIds exist. A different principal+name than
// raMlBlob, so no RoleAssignmentExists collision (Azure dedupes by
// scope+principal+role).

var mlClusterPids = enableMl ? mlCompute!.outputs.computeClusterPrincipalIds : []

module raMlComputeBlob 'modules/role-assignment/main.bicep' = [for (cc, i) in mlClusters: if (enableMl) {
  name: 'ra-ml-compute-blob-${i}'
  params: {
    roleAssignment: {
      principalId: mlClusterPids[i]
      roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      scopeResourceId: sa.outputs.id
      principalType: 'ServicePrincipal'
      description: 'ML compute cluster ${cc.name} MSI -> trials datalake (keyless read/write)'
    }
  }
  dependsOn: [ mlCompute ]
}]

// ----- Diagnostics on the major PaaS resources -----

resource kvExisting 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
  dependsOn: [ kv ]
}

resource saExisting 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: stName
  dependsOn: [ sa ]
}

resource aifExisting 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = if (config.foundry.enabled) {
  name: aifName
  dependsOn: [ foundry ]
}

resource aif2Existing 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = if (enableSecondaryFoundry) {
  name: aif2Name
  dependsOn: [ foundry2 ]
}

resource diagKv 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law'
  scope: kvExisting
  properties: {
    workspaceId: law.outputs.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource diagSt 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law'
  scope: saExisting
  properties: {
    workspaceId: law.outputs.id
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource diagFoundry 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (config.foundry.enabled) {
  name: 'to-law'
  scope: aifExisting
  properties: {
    workspaceId: law.outputs.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource diagFoundry2 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableSecondaryFoundry) {
  name: 'to-law'
  scope: aif2Existing
  properties: {
    workspaceId: law.outputs.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource mlwExisting 'Microsoft.MachineLearningServices/workspaces@2024-10-01-preview' existing = if (enableMl) {
  name: mlwName
  dependsOn: [ mlWs ]
}

resource diagMl 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMl) {
  name: 'to-law'
  scope: mlwExisting
  properties: {
    workspaceId: law.outputs.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

// ----- Outputs (key-free) -----

output foundryAccountId string = config.foundry.enabled ? foundry!.outputs.id : ''
output foundryAccountEndpoint string = config.foundry.enabled ? foundry!.outputs.endpoint : ''
output foundryProjectId string = config.foundry.enabled ? foundryProj!.outputs.id : ''
output foundryDeploymentNames array = [for d in config.foundry.deployments: d.name]
output secondaryFoundryAccountId string = enableSecondaryFoundry ? foundry2!.outputs.id : ''
output secondaryFoundryAccountEndpoint string = enableSecondaryFoundry ? foundry2!.outputs.endpoint : ''
output secondaryFoundryProjectId string = enableSecondaryFoundry ? foundry2Proj!.outputs.id : ''
output secondaryFoundryLocation string = enableSecondaryFoundry ? secondaryLocation : ''
output secondaryFoundryDeploymentNames array = enableSecondaryFoundry ? map(config.secondaryFoundry!.deployments, d => d.name) : []
output keyVaultId string = kv.outputs.id
output keyVaultUri string = kv.outputs.uri
output storageAccountId string = sa.outputs.id
output managedIdentityId string = mi.outputs.id
output managedIdentityPrincipalId string = mi.outputs.principalId
output managedIdentityClientId string = mi.outputs.clientId
output logAnalyticsWorkspaceId string = law.outputs.id
output appInsightsId string = appi.outputs.id
output aiSearchId string = enableSearch ? (srch!.outputs.id) : ''

// ----- Azure Machine Learning (feature 007) -----
output mlEnabled bool = enableMl
output mlWorkspaceId string = enableMl ? mlWs!.outputs.id : ''
output mlWorkspaceName string = enableMl ? mlWs!.outputs.name : ''
output mlComputeInstanceNames array = enableMl ? mlCompute!.outputs.computeInstanceNames : []
output mlComputeClusterNames array = enableMl ? mlCompute!.outputs.computeClusterNames : []

// ----- Matrix homeserver (feature 003) -----

// VNet sits behind the same enableMatrix flag so disabling matrix tears
// the network down too (no orphan cost).
module matrixNet 'modules/network/main.bicep' = if (enableMatrix) {
  name: 'matrix-net'
  params: {
    name: vnetName
    location: config.location
    tags: tags
  }
}

module matrixShare 'modules/matrix/file-share.bicep' = if (enableMatrix) {
  name: 'matrix-share'
  params: {
    storageAccountName: stName
    shareName: 'continuwuity-data'
    quotaGiB: enableMatrix ? config.matrix!.shareQuotaGiB : 5
  }
  dependsOn: [ sa ]
}

module matrixEnv 'modules/matrix/environment.bicep' = if (enableMatrix) {
  name: 'matrix-env'
  params: {
    name: caeName
    location: config.location
    tags: tags
    logAnalyticsWorkspaceId: law.outputs.id
    storageAccountName: stName
    fileShareName: 'continuwuity-data'
    storageMountName: 'continuwuity-data'
    infrastructureSubnetId: enableMatrix ? matrixNet!.outputs.acaSubnetId : ''
  }
  dependsOn: [ matrixShare, matrixNet ]
}

module matrixApp 'modules/matrix/homeserver.bicep' = if (enableMatrix) {
  name: 'matrix-app'
  params: {
    name: caName
    location: config.location
    tags: tags
    environmentId: enableMatrix ? matrixEnv!.outputs.id : ''
    userAssignedIdentityResourceId: mi.outputs.id
    userAssignedIdentityClientId: mi.outputs.clientId
    keyVaultUri: kv.outputs.uri
    continuwuityImage: enableMatrix ? config.matrix!.continuwuityImage : ''
    cloudflaredImage: enableMatrix ? config.matrix!.cloudflaredImage : ''
    enableCloudflareTunnel: enableMatrix ? config.matrix!.enableCloudflareTunnel : false
    serverName: enableMatrix ? config.matrix!.hostname : 'x'
    minReplicas: enableMatrix ? config.matrix!.minReplicas : 1
    maxReplicas: enableMatrix ? config.matrix!.maxReplicas : 1
    homeserverCpu: enableMatrix ? config.matrix!.homeserverCpu : '0.5'
    homeserverMemory: enableMatrix ? config.matrix!.homeserverMemory : '1Gi'
    cloudflaredCpu: enableMatrix ? config.matrix!.cloudflaredCpu : '0.25'
    cloudflaredMemory: enableMatrix ? config.matrix!.cloudflaredMemory : '0.5Gi'
    storageMountName: 'continuwuity-data'
  }
  dependsOn: [ matrixEnv, raKv ]
}

output matrixEnabled bool = enableMatrix
output matrixAppId string = enableMatrix ? matrixApp!.outputs.id : ''
output matrixAppFqdn string = enableMatrix ? matrixApp!.outputs.fqdn : ''
output matrixVnetId string = enableMatrix ? matrixNet!.outputs.id : ''
