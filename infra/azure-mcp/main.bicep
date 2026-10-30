// infra/azure-mcp/main.bicep
// Resource-group-scope entry point for the Azure MCP Claude connector
// (feature 016). Deploys into the workload resource group created by
// infra/main.bicep and reuses its Log Analytics workspace, Key Vault,
// storage account and Container Registry.
//
// Why a second entry point (see specs/016-azure-mcp-connector/plan.md,
// Complexity Tracking): the Entra app registration is a Microsoft Graph
// resource. Deploying it needs directory permissions that the GitHub OIDC
// principal deliberately does not hold (Constitution III), so this stack is
// deployed by the operator via scripts/deploy-azure-mcp.sh, not by CI.

targetScope = 'resourceGroup'

import { azureMcpDeploymentConfig } from '../shared/types.bicep'
import {
  law as nameLaw
  kv as nameKv
  storage as nameStorage
  mi as nameMi
  cae as nameCae
  ca as nameCa
  entraApp as nameEntraApp
} from '../shared/naming.bicep'
import { standardTags } from '../shared/tags.bicep'

@description('Required. Typed configuration; comes from infra/parameters/azure-mcp.<env>.bicepparam.')
param config azureMcpDeploymentConfig

@description('Stable timestamp threaded into tags so all child resources see the same value.')
param deployedAt string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

var mcp = config.azureMcp
var env = config.environment
var loc = config.location
var wl = config.workloadName
var baseInstance = config.?instance ?? ''
var mcpInstance = empty(baseInstance) ? 'mcp' : '${baseInstance}-mcp'

// Same seed as infra/main.bicep, so the shared globally-unique names resolve.
var uniqueSeed = '${subscription().subscriptionId}-${resourceGroup().name}'
var tags = standardTags(env, wl, config.owner, config.costCenter, deployedAt)

// ----- Names -----
var lawName = nameLaw(wl, env, loc, baseInstance)
var kvName = nameKv(wl, env, loc, baseInstance, uniqueSeed)
var stName = nameStorage(wl, env, loc, baseInstance, uniqueSeed)
var caeName = nameCae(wl, env, loc, mcpInstance)
var caName = nameCa(wl, env, loc, mcpInstance)
var gatewayMiName = nameMi(wl, env, loc, '${mcpInstance}-gw')
var azureMcpMiName = nameMi(wl, env, loc, '${mcpInstance}-srv')
var appUniqueName = nameEntraApp(wl, env, loc, mcpInstance)

var masterKeySecretName = 'azure-mcp-gateway-master-key'
var storageTableName = 'azuremcpgateway'
var allowedPrincipalIds = filter(map(split(mcp.allowedPrincipalIds, ','), p => trim(p)), p => !empty(p))

// ----- Shared resources from the main stack -----

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: lawName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

resource masterKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  parent: kv
  name: masterKeySecretName
}

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: stName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: mcp.containerRegistryName
}

// ----- Identities -----
// Two identities so the internet-facing gateway and the Azure-facing MCP
// server hold disjoint permissions.

module gatewayMi '../modules/managed-identity/main.bicep' = {
  name: 'azmcp-mi-gateway'
  params: {
    name: gatewayMiName
    location: loc
    tags: tags
  }
}

module azureMcpMi '../modules/managed-identity/main.bicep' = {
  name: 'azmcp-mi-server'
  params: {
    name: azureMcpMiName
    location: loc
    tags: tags
  }
}

// ----- Environment (public) -----

module cae '../modules/azure-mcp/environment.bicep' = {
  name: 'azmcp-cae'
  params: {
    name: caeName
    location: loc
    tags: tags
    logAnalyticsWorkspaceId: law.id
  }
}

var fqdn = '${caName}.${cae.outputs.defaultDomain}'
var publicBaseUrl = 'https://${fqdn}'

// ----- Entra ID -----

module entra '../modules/azure-mcp/entra-app.bicep' = {
  name: 'azmcp-entra'
  params: {
    uniqueName: appUniqueName
    displayName: '${wl}-${env} Azure MCP connector'
    redirectUri: '${publicBaseUrl}/auth/callback'
    gatewayPrincipalId: gatewayMi.outputs.principalId
    allowedPrincipalIds: allowedPrincipalIds
  }
}

// ----- RBAC -----

module raAzureMcpSubscription '../modules/role-assignment/subscription.bicep' = [for role in mcp.subscriptionRoles: {
  name: 'ra-azmcp-sub-${toLower(replace(role, ' ', '-'))}'
  scope: subscription()
  params: {
    principalId: azureMcpMi.outputs.principalId
    roleDefinitionIdOrName: role
    assignmentDescription: 'Azure MCP Server MI -> subscription (${role})'
  }
}]

module raGatewayAcr '../modules/role-assignment/main.bicep' = {
  name: 'ra-azmcp-gw-acr'
  params: {
    roleAssignment: {
      principalId: gatewayMi.outputs.principalId
      roleDefinitionIdOrName: 'AcrPull'
      scopeResourceId: acr.id
      scopeKind: 'containerRegistry'
      principalType: 'ServicePrincipal'
      description: 'MCP gateway MI -> pull gateway image'
    }
  }
}

module raGatewayTable '../modules/role-assignment/main.bicep' = {
  name: 'ra-azmcp-gw-table'
  params: {
    roleAssignment: {
      principalId: gatewayMi.outputs.principalId
      roleDefinitionIdOrName: 'Storage Table Data Contributor'
      scopeResourceId: sa.id
      scopeKind: 'storageAccount'
      principalType: 'ServicePrincipal'
      description: 'MCP gateway MI -> OAuth state table'
    }
  }
}

module raGatewaySecret '../modules/role-assignment/main.bicep' = {
  name: 'ra-azmcp-gw-secret'
  params: {
    roleAssignment: {
      principalId: gatewayMi.outputs.principalId
      roleDefinitionIdOrName: 'Key Vault Secrets User'
      scopeResourceId: masterKey.id
      scopeKind: 'keyVaultSecret'
      principalType: 'ServicePrincipal'
      description: 'MCP gateway MI -> its master key secret only'
    }
  }
}

// ----- App -----

module app '../modules/azure-mcp/container-app.bicep' = {
  name: 'azmcp-app'
  params: {
    name: caName
    location: loc
    tags: tags
    environmentId: cae.outputs.id
    publicBaseUrl: publicBaseUrl
    gatewayIdentityId: gatewayMi.outputs.id
    gatewayIdentityClientId: gatewayMi.outputs.clientId
    azureMcpIdentityId: azureMcpMi.outputs.id
    azureMcpIdentityClientId: azureMcpMi.outputs.clientId
    registryServer: acr.properties.loginServer
    gatewayImage: '${acr.properties.loginServer}/${mcp.gatewayImageRepository}:${mcp.gatewayImageTag}'
    azureMcpImage: mcp.azureMcpImage
    entraClientId: entra.outputs.clientId
    keyVaultUri: kv.properties.vaultUri
    masterKeySecretName: masterKeySecretName
    storageAccountName: sa.name
    storageTableEndpoint: sa.properties.primaryEndpoints.table
    storageTableName: storageTableName
    allowedPrincipalIds: join(allowedPrincipalIds, ',')
    readOnly: mcp.readOnly
    namespaces: mcp.namespaces
    minReplicas: mcp.minReplicas
    maxReplicas: mcp.maxReplicas
    gatewayCpu: mcp.gatewayCpu
    gatewayMemory: mcp.gatewayMemory
    azureMcpCpu: mcp.azureMcpCpu
    azureMcpMemory: mcp.azureMcpMemory
  }
  dependsOn: [ raGatewayAcr, raGatewayTable, raGatewaySecret, raAzureMcpSubscription ]
}

// ----- Outputs (no secrets) -----

output mcpServerUrl string = '${publicBaseUrl}/mcp'
output containerAppName string = app.outputs.name
output entraAppClientId string = entra.outputs.clientId
