// modules/role-assignment/main.bicep
// Idempotent role assignment at resource-group or storage-account scope.

metadata description = 'Idempotent RBAC assignment using guid(scope, principalId, roleDefinitionId).'

import { roleAssignmentSpec } from '../../shared/types.bicep'

param roleAssignment roleAssignmentSpec

// Built-in role name -> ID map (extend as needed).
var roleMap = {
  Owner:                                  '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
  Contributor:                            'b24988ac-6180-42a0-ab88-20f7382dd24c'
  Reader:                                 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  'User Access Administrator':            '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
  'Cognitive Services User':              'a97b65f3-24c7-4388-baec-2e87135dc908'
  'Cognitive Services Contributor':       '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
  'Cognitive Services OpenAI User':       '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  'Cognitive Services OpenAI Contributor':'a001fd3d-188f-4b5d-821b-7da978bf7442'
  'Storage Blob Data Contributor':        'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  'Storage Blob Data Owner':              'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  'Storage File Data Privileged Contributor': '69566ab7-960f-475b-8e7c-b3118f30c6bd'
  'Key Vault Secrets User':               '4633458b-17de-408a-b874-0445c86b69e6'
  'Key Vault Secrets Officer':            'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  'AzureML Data Scientist':               'f6c7c914-8db3-469d-8ca1-694a8f32e121'
  'Search Index Data Contributor':        '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  'Search Service Contributor':           '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
}

var roleDefId = contains(roleMap, roleAssignment.roleDefinitionIdOrName)
  ? roleMap[roleAssignment.roleDefinitionIdOrName]
  : roleAssignment.roleDefinitionIdOrName
var scopeKind = roleAssignment.?scopeKind ?? 'resourceGroup'

resource storageScope 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(roleAssignment.scopeResourceId, '/'))
}

resource raResourceGroup 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (scopeKind == 'resourceGroup') {
  name: guid(roleAssignment.scopeResourceId, roleAssignment.principalId, roleDefId)
  scope: resourceGroup()
  properties: {
    principalId: roleAssignment.principalId
    principalType: roleAssignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: roleAssignment.?description ?? null
  }
}

resource raStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (scopeKind == 'storageAccount') {
  name: guid(roleAssignment.scopeResourceId, roleAssignment.principalId, roleDefId)
  scope: storageScope
  properties: {
    principalId: roleAssignment.principalId
    principalType: roleAssignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: roleAssignment.?description ?? null
  }
}

output id string = scopeKind == 'storageAccount' ? raStorage!.id : raResourceGroup!.id
