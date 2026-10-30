// infra/parameters/azure-mcp.dev.bicepparam
// Azure MCP Claude connector (feature 016), dev. Deployed by
// scripts/deploy-azure-mcp.sh into the main stack's resource group.
//
// Allowed principals are sourced at compile time from
// $env:AZURE_MCP_ALLOWED_PRINCIPAL_IDS (the deploy script defaults it to
// the signed-in operator); object IDs MUST NOT be committed (Constitution II).

using '../azure-mcp/main.bicep'

param config = {
  environment: 'dev'
  location: 'eastus2'
  workloadName: 'aio'
  owner: 'mikkeyboi'           // GitHub handle, NOT email
  costCenter: 'poc'
  azureMcp: {
    // Azure MCP Server 4.0.0 (beta, preferred over 3.0.0 stable). Pinned.
    azureMcpImage: 'mcr.microsoft.com/azure-sdk/azure-mcp:4.0.0-beta.4'
    // Same registry the ML workspace auto-attached (feature 011).
    containerRegistryName: '51119126436640639d290bc8189dcbbf'
    gatewayImageRepository: 'azure-mcp-gateway'
    // Content hash of apps/azure-mcp-gateway, computed by the deploy script,
    // so any gateway code change gets a new immutable tag automatically.
    gatewayImageTag: readEnvironmentVariable('AZURE_MCP_GATEWAY_IMAGE_TAG', '')
    allowedPrincipalIds: readEnvironmentVariable('AZURE_MCP_ALLOWED_PRINCIPAL_IDS', '')
    // Read everywhere in the subscription...
    subscriptionRoles: [ 'Reader' ]
    // ...and manage Foundry in this resource group (both Foundry accounts):
    // control plane (accounts, projects, model deployments) + data plane
    // (inference, agents). No role that can write role assignments.
    resourceGroupRoles: [ 'Cognitive Services Contributor', 'Foundry User' ]
    // Writes are needed for deployments/agents; outside the roles above
    // Azure refuses them.
    readOnly: false
    namespaces: []
    // Always-on: a scale-from-zero cold start measured ~56 s (two image
    // pulls + .NET start), well past Claude's 10 s discovery timeout.
    minReplicas: 1
    maxReplicas: 1
    gatewayCpu: '0.25'
    gatewayMemory: '0.5Gi'
    azureMcpCpu: '0.5'
    azureMcpMemory: '1Gi'
  }
}
