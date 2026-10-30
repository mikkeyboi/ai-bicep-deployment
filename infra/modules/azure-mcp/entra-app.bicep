// modules/azure-mcp/entra-app.bicep
// Entra ID app registration that both signs users in for the MCP gateway
// and is the audience Azure MCP Server validates on every inbound call.
//
// - Single-tenant, v2 access tokens, one delegated scope
//   (Mcp.Tools.ReadWrite: the scope Azure MCP Server requires).
// - No client secret: the gateway authenticates with a federated identity
//   credential that trusts its user-assigned managed identity.
// - The enterprise app requires assignment; only allowedPrincipalIds are
//   assigned, so nobody else in the tenant can even complete sign-in.
// - Tenant-wide consent is granted here, so first sign-in shows no consent
//   prompt for this app's own scope or offline_access.

metadata description = 'Entra app + service principal + MI federated credential + assignments for the Azure MCP gateway.'

extension microsoftGraphV1

@description('Directory-wide unique key for the app registration (naming.bicep entraApp()).')
param uniqueName string

param displayName string

@description('Gateway OAuth callback, e.g. https://<fqdn>/auth/callback.')
param redirectUri string

@description('principalId of the gateway user-assigned managed identity (federated credential subject).')
param gatewayPrincipalId string

@description('Entra object IDs to assign to the enterprise app (users or groups).')
param allowedPrincipalIds array

@description('Delegated scope value. Azure MCP Server requires exactly Mcp.Tools.ReadWrite.')
param scopeValue string = 'Mcp.Tools.ReadWrite'

var scopeId = guid(uniqueName, scopeValue)
var defaultAccessAppRoleId = '00000000-0000-0000-0000-000000000000'
// Well-known appId of Microsoft Graph (same in every tenant).
var microsoftGraphAppId = '00000003-0000-0000-c000-000000000000'

var apiSettings = {
  requestedAccessTokenVersion: 2
  oauth2PermissionScopes: [
    {
      id: scopeId
      type: 'User'
      value: scopeValue
      isEnabled: true
      adminConsentDisplayName: 'Use Azure MCP tools'
      adminConsentDescription: 'Allows the app to call Azure MCP Server tools on behalf of the signed-in user.'
      userConsentDisplayName: 'Use Azure MCP tools'
      userConsentDescription: 'Allows the app to call Azure MCP Server tools on your behalf.'
    }
  ]
}
var webSettings = {
  redirectUris: [ redirectUri ]
  implicitGrantSettings: {
    enableAccessTokenIssuance: false
    enableIdTokenIssuance: false
  }
}

resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: uniqueName
  displayName: displayName
  signInAudience: 'AzureADMyOrg'
  api: apiSettings
  web: webSettings
}

// identifierUris can only reference the appId once it exists, hence the
// second declaration of the same uniqueName (Microsoft's azmcp templates use
// the same pattern). Every other property is repeated so neither PUT clears it.
resource appWithIdentifierUri 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: uniqueName
  displayName: displayName
  signInAudience: 'AzureADMyOrg'
  identifierUris: [ 'api://${app.appId}' ]
  api: apiSettings
  web: webSettings
}

resource gatewayCredential 'Microsoft.Graph/applications/federatedIdentityCredentials@v1.0' = {
  name: '${appWithIdentifierUri.uniqueName}/gateway-managed-identity'
  description: 'MCP gateway user-assigned managed identity (secretless client assertion).'
  audiences: [ 'api://AzureADTokenExchange' ]
  issuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
  subject: gatewayPrincipalId
}

resource servicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: appWithIdentifierUri.appId
  appRoleAssignmentRequired: true
}

resource assignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for principalId in allowedPrincipalIds: {
  appRoleId: defaultAccessAppRoleId
  principalId: principalId
  resourceId: servicePrincipal.id
}]

resource microsoftGraph 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: microsoftGraphAppId
}

resource consentOwnScope 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: servicePrincipal.id
  consentType: 'AllPrincipals'
  resourceId: servicePrincipal.id
  scope: scopeValue
}

resource consentOfflineAccess 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: servicePrincipal.id
  consentType: 'AllPrincipals'
  resourceId: microsoftGraph.id
  scope: 'offline_access'
}

output clientId string = appWithIdentifierUri.appId
output identifierUri string = 'api://${appWithIdentifierUri.appId}'
output servicePrincipalId string = servicePrincipal.id
