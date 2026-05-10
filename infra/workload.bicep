// infra/workload.bicep
// Resource-group-scope orchestrator. Receives the typed config + tags
// from main.bicep and invokes every module per
// specs/001-aio-foundation/contracts/modules.contract.md § workload.

targetScope = 'resourceGroup'

import { environmentConfig } from 'shared/types.bicep'
import {
  law as nameLaw
  ai as nameAi
  mi as nameMi
  kv as nameKv
  storage as nameStorage
  openai as nameOpenAi
  foundry as nameFoundry
  foundryHub as nameFoundryHub
  project as nameProject
  search as nameSearch
} from 'shared/naming.bicep'

param config environmentConfig
param tags object
param uniqueSeed string

// ----- Names -----
var instance = config.?instance ?? ''

var laName    = nameLaw       (config.workloadName, config.environment, config.location, instance)
var aiName    = nameAi        (config.workloadName, config.environment, config.location, instance)
var miName    = nameMi        (config.workloadName, config.environment, config.location, instance)
var kvName    = nameKv        (config.workloadName, config.environment, config.location, instance, uniqueSeed)
var stName    = nameStorage   (config.workloadName, config.environment, config.location, instance, uniqueSeed)
var oaiName   = nameOpenAi    (config.workloadName, config.environment, config.location, instance, uniqueSeed)
var fdyName   = nameFoundry   (config.workloadName, config.environment, config.location, instance, uniqueSeed)
var hubName   = nameFoundryHub(config.workloadName, config.environment, config.location, instance)
var projName  = nameProject   (config.workloadName, config.environment, config.location, instance)
var srchName  = nameSearch    (config.workloadName, config.environment, config.location, instance, uniqueSeed)

var pnaResource = config.enablePublicNetworkAccess ? 'Enabled' : 'Disabled'
var enableSearch = config.?enableAiSearch ?? false

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

// ----- OpenAI account + deployments -----

module oai 'modules/openai-account/main.bicep' = if (config.openAi.enabled) {
  name: 'oai'
  params: {
    name: oaiName
    location: config.location
    tags: tags
    customSubdomain: oaiName
    publicNetworkAccess: pnaResource
  }
}

module oaiDeps 'modules/openai-deployment/main.bicep' = [for d in config.openAi.deployments: if (config.openAi.enabled) {
  name: 'oaid-${d.name}'
  params: {
    accountName: oaiName
    deployment: d
  }
  dependsOn: [ oai ]
}]

// ----- Claude (Foundry AIServices) account + deployments -----

module fdy 'modules/foundry-claude-account/main.bicep' = if (config.claude.enabled) {
  name: 'fdy'
  params: {
    name: fdyName
    location: config.location
    tags: tags
    customSubdomain: fdyName
    publicNetworkAccess: pnaResource
  }
}

module fdyDeps 'modules/foundry-claude-deployment/main.bicep' = [for d in config.claude.deployments: if (config.claude.enabled) {
  name: 'fdyd-${d.name}'
  params: {
    accountName: fdyName
    deployment: d
  }
  dependsOn: [ fdy ]
}]

// ----- Foundry hub + project -----

module hub 'modules/foundry-hub/main.bicep' = {
  name: 'hub'
  params: {
    name: hubName
    location: config.location
    tags: tags
    keyVaultId: kv.outputs.id
    storageAccountId: sa.outputs.id
    appInsightsId: appi.outputs.id
    managedIdentityId: mi.outputs.id
    aiSearchId: enableSearch ? (srch!.outputs.id) : ''
  }
}

module proj 'modules/foundry-project/main.bicep' = {
  name: 'proj'
  params: {
    name: projName
    location: config.location
    tags: tags
    hubId: hub.outputs.id
  }
}

// ----- Foundry connections to OpenAI + Claude accounts -----

module connOai 'modules/foundry-connection/main.bicep' = if (config.openAi.enabled) {
  name: 'conn-oai'
  params: {
    hubName: hubName
    connection: {
      name: 'aoai-conn'
      category: 'AzureOpenAI'
      targetResourceId: oai!.outputs.id
      authType: 'AAD'
    }
  }
  dependsOn: [ hub ]
}

module connFdy 'modules/foundry-connection/main.bicep' = if (config.claude.enabled) {
  name: 'conn-fdy'
  params: {
    hubName: hubName
    connection: {
      name: 'aiservices-conn'
      category: 'AIServices'
      targetResourceId: fdy!.outputs.id
      authType: 'AAD'
    }
  }
  dependsOn: [ hub ]
}

// ----- RBAC: grant the workload MI least-privilege roles -----

var miPid = mi.outputs.principalId

module raOpenAi 'modules/role-assignment/main.bicep' = if (config.openAi.enabled) {
  name: 'ra-mi-oai'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
      scopeResourceId: oai!.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> Azure OpenAI inference'
    }
  }
}

module raFdy 'modules/role-assignment/main.bicep' = if (config.claude.enabled) {
  name: 'ra-mi-fdy'
  params: {
    roleAssignment: {
      principalId: miPid
      roleDefinitionIdOrName: 'Cognitive Services User'
      scopeResourceId: fdy!.outputs.id
      principalType: 'ServicePrincipal'
      description: 'Workload MI -> Foundry/Claude inference'
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
// diagnosticSettings is an extension resource; declare inline scoped
// to each `existing` resource symbol. Modules can't take resource scope.

resource kvExisting 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
  dependsOn: [ kv ]
}

resource saExisting 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: stName
  dependsOn: [ sa ]
}

resource oaiExisting 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (config.openAi.enabled) {
  name: oaiName
  dependsOn: [ oai ]
}

resource fdyExisting 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (config.claude.enabled) {
  name: fdyName
  dependsOn: [ fdy ]
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

resource diagOai 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (config.openAi.enabled) {
  name: 'to-law'
  scope: oaiExisting
  properties: {
    workspaceId: law.outputs.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource diagFdy 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (config.claude.enabled) {
  name: 'to-law'
  scope: fdyExisting
  properties: {
    workspaceId: law.outputs.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

// ----- Outputs (key-free) -----

output foundryHubId string = hub.outputs.id
output foundryProjectId string = proj.outputs.id
output openAiAccountId string = config.openAi.enabled ? oai!.outputs.id : ''
output openAiEndpoint string = config.openAi.enabled ? oai!.outputs.endpoint : ''
output openAiDeploymentNames array = [for d in config.openAi.deployments: d.name]
output claudeAccountId string = config.claude.enabled ? fdy!.outputs.id : ''
output claudeEndpoint string = config.claude.enabled ? fdy!.outputs.endpoint : ''
output claudeDeploymentNames array = [for d in config.claude.deployments: d.name]
output keyVaultId string = kv.outputs.id
output keyVaultUri string = kv.outputs.uri
output storageAccountId string = sa.outputs.id
output managedIdentityId string = mi.outputs.id
output managedIdentityPrincipalId string = mi.outputs.principalId
output managedIdentityClientId string = mi.outputs.clientId
output logAnalyticsWorkspaceId string = law.outputs.id
output appInsightsId string = appi.outputs.id
output aiSearchId string = enableSearch ? (srch!.outputs.id) : ''
