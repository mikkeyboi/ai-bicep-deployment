// infra/parameters/main.test.bicepparam
// TEST environment (placeholder — copy of dev with test toggles).
// Update model list / capacity before promoting from dev.
//
// Constitution VIII (v1.1.0): first-party Azure OpenAI only.

using '../main.bicep'

param config = {
  environment: 'test'
  location: 'eastus2'
  workloadName: 'aio'
  owner: 'mikkeyboi'
  costCenter: 'poc'
  enablePurgeProtection: false
  enablePublicNetworkAccess: true
  diagnosticsRetentionDays: 30
  enableAiSearch: true
  foundry: {
    enabled: true
    deployments: [
      {
        name: 'gpt-4o'
        model: { format: 'OpenAI', name: 'gpt-4o', version: '2024-11-20' }
        sku:   { name: 'Standard', capacity: 30 }
      }
      {
        name: 'text-embedding-3-large'
        model: { format: 'OpenAI', name: 'text-embedding-3-large', version: '1' }
        sku:   { name: 'Standard', capacity: 60 }
      }
    ]
  }
}
