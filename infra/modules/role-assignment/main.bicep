// modules/role-assignment/main.bicep
// Idempotent role assignment at resource-group, storage-account,
// container-registry, blob-container or Key Vault secret scope.

metadata description = 'Idempotent RBAC assignment using guid(scope, principalId, roleDefinitionId).'

import { roleAssignmentSpec } from '../../shared/types.bicep'

param roleAssignment roleAssignmentSpec

// Built-in role name -> ID map (extend as needed). Exported so the
// subscription-scope variant (subscription.bicep) shares one table; the
// built-in GUIDs stay in this gitleaks-allowlisted file.
@export()
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
  'Storage Blob Delegator':               'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'
  'Storage Table Data Contributor':       '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  AcrPull:                                '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  'Key Vault Secrets User':               '4633458b-17de-408a-b874-0445c86b69e6'
  'Key Vault Secrets Officer':            'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  'Foundry User':                         '53ca6127-db72-4b80-b1b0-d745d6d5456d'
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

resource registryScope 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (scopeKind == 'containerRegistry') {
  name: last(split(roleAssignment.scopeResourceId, '/'))
}

// .../vaults/<vault>/secrets/<secret> -> '<vault>/<secret>'
// .../storageAccounts/<acct>/blobServices/default/containers/<c> -> '<acct>/default/<c>'
var idSegments = split(roleAssignment.scopeResourceId, '/')
resource keyVaultSecretScope 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = if (scopeKind == 'keyVaultSecret') {
  name: '${idSegments[max(length(idSegments) - 3, 0)]}/${last(idSegments)}'
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
  name: guid('storageAccount', roleAssignment.scopeResourceId, roleAssignment.principalId, roleDefId)
  scope: storageScope
  properties: {
    principalId: roleAssignment.principalId
    principalType: roleAssignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: roleAssignment.?description ?? null
  }
}

resource blobContainerScope 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = if (scopeKind == 'blobContainer') {
  name: '${idSegments[max(length(idSegments) - 5, 0)]}/default/${last(idSegments)}'
}

resource raBlobContainer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (scopeKind == 'blobContainer') {
  name: guid('blobContainer', roleAssignment.scopeResourceId, roleAssignment.principalId, roleDefId)
  scope: blobContainerScope
  properties: {
    principalId: roleAssignment.principalId
    principalType: roleAssignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: roleAssignment.?description ?? null
  }
}

resource raRegistry 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (scopeKind == 'containerRegistry') {
  name: guid('containerRegistry', roleAssignment.scopeResourceId, roleAssignment.principalId, roleDefId)
  scope: registryScope
  properties: {
    principalId: roleAssignment.principalId
    principalType: roleAssignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: roleAssignment.?description ?? null
  }
}

resource raKeyVaultSecret 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (scopeKind == 'keyVaultSecret') {
  name: guid('keyVaultSecret', roleAssignment.scopeResourceId, roleAssignment.principalId, roleDefId)
  scope: keyVaultSecretScope
  properties: {
    principalId: roleAssignment.principalId
    principalType: roleAssignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    description: roleAssignment.?description ?? null
  }
}

output id string = scopeKind == 'storageAccount'
  ? raStorage!.id
  : scopeKind == 'containerRegistry'
    ? raRegistry!.id
    : scopeKind == 'keyVaultSecret'
      ? raKeyVaultSecret!.id
      : scopeKind == 'blobContainer' ? raBlobContainer!.id : raResourceGroup!.id
