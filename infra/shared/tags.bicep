// infra/shared/tags.bicep
// Standard tag map producer per Constitution Principle V.

metadata description = 'Standard tag map for every taggable resource.'

@export()
@description('Build the standard tag map. Pass deployedAt from main.bicep so all child modules see the same value within one deployment.')
func standardTags(environment string, workload string, owner string, costCenter string, deployedAt string) object => {
  environment: environment
  workload: workload
  owner: owner
  costCenter: costCenter
  managedBy: 'bicep'
  repo: 'mikkeyboi/ai-bicep-deployment'
  deployedAt: deployedAt
}
