// infra/parameters/main.prod.bicepparam
// PROD environment (placeholder — TIGHTEN before promoting).
// Differences from dev: purge protection ON, public network access OFF,
// no shared-key access on storage (handled by env=='prod' branch in workload).

using '../main.bicep'

param config = {
  environment: 'prod'
  location: 'eastus2'
  workloadName: 'aio'
  owner: 'mikkeyboi'
  costCenter: 'prod'
  enablePurgeProtection: true
  enablePublicNetworkAccess: false
  diagnosticsRetentionDays: 90
  enableAiSearch: true
  openAi: {
    enabled: true
    deployments: [
      {
        name: 'gpt-5-chat'
        model: { format: 'OpenAI', name: 'gpt-5-chat', version: '2025-08-07' }
        sku:   { name: 'GlobalStandard', capacity: 100 }
      }
      {
        name: 'gpt-4o'
        model: { format: 'OpenAI', name: 'gpt-4o', version: '2024-11-20' }
        sku:   { name: 'Standard', capacity: 100 }
      }
      {
        name: 'text-embedding-3-large'
        model: { format: 'OpenAI', name: 'text-embedding-3-large', version: '1' }
        sku:   { name: 'Standard', capacity: 240 }
      }
    ]
  }
  claude: {
    enabled: true
    deployments: [
      {
        name: 'claude-sonnet-4-5'
        model: { format: 'Anthropic', name: 'claude-sonnet-4-5', version: '20250929' }
        sku:   { name: 'GlobalStandard', capacity: 1 }
      }
      {
        name: 'claude-haiku-4-5'
        model: { format: 'Anthropic', name: 'claude-haiku-4-5', version: '20251001' }
        sku:   { name: 'GlobalStandard', capacity: 1 }
      }
    ]
  }
}
