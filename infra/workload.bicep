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

module raFoundry2 'modules/role-assignment/main.bicep' = if (enableSecondaryFoundry) {
  name: 'ra-mi-aif2'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Cognitive Services User'
      scopeResourceId: foundry2!.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> secondary Foundry account inference'
    }
  }
}

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
