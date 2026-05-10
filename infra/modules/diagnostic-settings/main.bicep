// modules/diagnostic-settings/main.bicep
// Generic diagnostic-settings helper. Caller passes a resource symbol via
// `scope` on the module invocation, e.g.:
//   module diag 'modules/diagnostic-settings/main.bicep' = {
//     name: 'diag-kv'
//     scope: kv                       // existing resource symbol
//     params: { name: 'to-law', workspaceResourceId: law.outputs.id }
//   }
// Bicep treats Microsoft.Insights/diagnosticSettings as an extension
// resource, so the surrounding `scope` attribute correctly targets any
// resource that supports diagnostics.

metadata description = 'Generic diagnostic-settings extension resource.'

param name string
param workspaceResourceId string

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: name
  properties: {
    workspaceId: workspaceResourceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output id string = diag.id
