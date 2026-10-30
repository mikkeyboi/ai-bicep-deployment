// modules/role-assignment/subscription.bicep
// Idempotent role assignment at subscription scope (feature 016: the Azure
// MCP Server identity's read access to the subscription's resources).

metadata description = 'Idempotent subscription-scope RBAC assignment sharing the role table in main.bicep.'

targetScope = 'subscription'

import { roleMap } from 'main.bicep'

param principalId string
@description('Built-in role name from the shared role table, or a role definition GUID.')
param roleDefinitionIdOrName string
param principalType string = 'ServicePrincipal'
param assignmentDescription string = ''

var roleDefId = roleMap[?roleDefinitionIdOrName] ?? roleDefinitionIdOrName

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleDefId)
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: empty(assignmentDescription) ? null : assignmentDescription
  }
}

output id string = ra.id
