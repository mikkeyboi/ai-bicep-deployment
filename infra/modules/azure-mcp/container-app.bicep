// modules/azure-mcp/container-app.bicep
// One Container App, two containers sharing the replica's loopback:
//
//   internet --HTTPS--> [gateway :8000]  OAuth AS for Claude + Entra sign-in,
//                            |           principal allowlist, MCP proxy
//                            | http://127.0.0.1:5008, user's Entra token
//                            v
//                       [azure-mcp :5008] validates that token again
//                                         (incoming auth ON), then calls
//                                         Azure as its own managed identity
//
// Ingress targets only the gateway port. Azure MCP Server binds 127.0.0.1,
// so nothing outside the replica can reach it.

metadata description = 'Azure MCP Server + authenticating OAuth gateway sidecar pair on Container Apps.'

param name string
param location string
param tags object
param environmentId string

@description('Public origin of this app, e.g. https://<name>.<env default domain>.')
param publicBaseUrl string

param gatewayIdentityId string
param gatewayIdentityClientId string
param azureMcpIdentityId string
param azureMcpIdentityClientId string

param registryServer string
param gatewayImage string
param azureMcpImage string

@description('appId of the Entra app registration (gateway client + Azure MCP Server audience).')
param entraClientId string

param keyVaultUri string
param masterKeySecretName string

param storageAccountName string
param storageTableEndpoint string
param storageTableName string

@description('Comma-separated object IDs the gateway admits.')
param allowedPrincipalIds string

param readOnly bool
param namespaces array

@minValue(0)
param minReplicas int
@minValue(1)
param maxReplicas int

param gatewayCpu string
param gatewayMemory string
param azureMcpCpu string
param azureMcpMemory string

var gatewayPort = 8000
var azureMcpPort = 5008
var masterKeyRef = 'gateway-master-key'

var azureMcpArgs = flatten([
  [
    '--transport'
    'http'
    '--outgoing-auth-strategy'
    'UseHostingEnvironmentIdentity'
    '--mode'
    'namespace'
  ]
  readOnly ? [ '--read-only' ] : []
  flatten(map(namespaces, ns => [ '--namespace', ns ]))
])

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${gatewayIdentityId}': {}
      '${azureMcpIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: gatewayPort
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: gatewayIdentityId
        }
      ]
      secrets: [
        {
          name: masterKeyRef
          keyVaultUrl: '${keyVaultUri}secrets/${masterKeySecretName}'
          identity: gatewayIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: gatewayImage
          resources: {
            cpu: json(gatewayCpu)
            memory: gatewayMemory
          }
          env: [
            { name: 'PORT', value: string(gatewayPort) }
            { name: 'PUBLIC_BASE_URL', value: publicBaseUrl }
            { name: 'AZURE_TENANT_ID', value: tenant().tenantId }
            { name: 'ENTRA_CLIENT_ID', value: entraClientId }
            { name: 'GATEWAY_IDENTITY_CLIENT_ID', value: gatewayIdentityClientId }
            { name: 'GATEWAY_MASTER_KEY', secretRef: masterKeyRef }
            { name: 'ALLOWED_PRINCIPAL_IDS', value: allowedPrincipalIds }
            { name: 'AZURE_MCP_URL', value: 'http://127.0.0.1:${azureMcpPort}/' }
            { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
            { name: 'STORAGE_TABLE_ENDPOINT', value: storageTableEndpoint }
            { name: 'STORAGE_TABLE_NAME', value: storageTableName }
            // The gateway's own foundry_* tools act as the Azure MCP Server
            // identity, so they share its RBAC rather than widening the gateway's.
            { name: 'FOUNDRY_IDENTITY_CLIENT_ID', value: azureMcpIdentityClientId }
            { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
            { name: 'AZURE_RESOURCE_MANAGER_URL', value: environment().resourceManager }
          ]
          probes: [
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: gatewayPort
              }
              periodSeconds: 5
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: gatewayPort
              }
              periodSeconds: 30
            }
          ]
        }
        {
          // No probes: it listens on loopback only, which kubelet probes can't reach.
          name: 'azure-mcp'
          image: azureMcpImage
          args: azureMcpArgs
          resources: {
            cpu: json(azureMcpCpu)
            memory: azureMcpMemory
          }
          env: [
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'ASPNETCORE_URLS', value: 'http://127.0.0.1:${azureMcpPort}' }
            // Inbound: validate the gateway-forwarded user token.
            { name: 'AzureAd__Instance', value: environment().authentication.loginEndpoint }
            { name: 'AzureAd__TenantId', value: tenant().tenantId }
            { name: 'AzureAd__ClientId', value: entraClientId }
            // Outbound: this container's managed identity only.
            { name: 'AZURE_TOKEN_CREDENTIALS', value: 'managedidentitycredential' }
            { name: 'AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS', value: 'true' }
            { name: 'AZURE_CLIENT_ID', value: azureMcpIdentityClientId }
            { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
            { name: 'AZURE_MCP_COLLECT_TELEMETRY', value: 'false' }
            // Plain HTTP is only ever spoken on the replica's loopback (gateway ->
            // Azure MCP); public traffic is TLS-terminated at ACA ingress. Same
            // setting as Microsoft's azmcp ACA templates.
            { name: 'AZURE_MCP_DANGEROUSLY_DISABLE_HTTPS_REDIRECTION', value: 'true' }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output id string = app.id
output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
