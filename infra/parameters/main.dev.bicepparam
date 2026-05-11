// infra/parameters/main.dev.bicepparam
// Default development environment.
// Region: eastus2 — broadest first-party Azure OpenAI surface (GPT-5,
// GPT-4o, embeddings, image-gen with limited-access approval).
// Model versions/SKUs verified via `az cognitiveservices model list --location eastus2`.
//
// NOTE: gpt-4o and text-embedding-3-large are only offered as 'Standard'
// in eastus2 (NOT GlobalStandard). gpt-5-chat supports 'GlobalStandard'.
// Image models (gpt-image-1*) are gated; left commented.
//
// Constitution VIII (v1.1.0): no Azure Marketplace SaaS offers in this
// repo. Anthropic Claude / Cohere / Mistral premium tiers in Foundry
// are out of scope (they bill outside Azure consumption credits).

using '../main.bicep'

param config = {
  environment: 'dev'
  location: 'eastus2'
  workloadName: 'aio'
  owner: 'mikkeyboi'           // GitHub handle, NOT email
  costCenter: 'poc'
  enablePurgeProtection: false
  enablePublicNetworkAccess: true
  diagnosticsRetentionDays: 30
  enableAiSearch: true
  openAi: {
    enabled: true
    deployments: [
      {
        name: 'gpt-5-chat'
        model: { format: 'OpenAI', name: 'gpt-5-chat', version: '2025-08-07' }
        sku:   { name: 'GlobalStandard', capacity: 50 }
      }
      {
        name: 'gpt-4o'
        model: { format: 'OpenAI', name: 'gpt-4o', version: '2024-11-20' }
        sku:   { name: 'Standard', capacity: 50 }
      }
      {
        name: 'text-embedding-3-large'
        model: { format: 'OpenAI', name: 'text-embedding-3-large', version: '1' }
        sku:   { name: 'Standard', capacity: 120 }
      }
      // ---- Disabled-by-default, parameter-only image models ----
      // First-party Azure OpenAI; consumption-billed (Constitution VIII OK).
      // Requires Microsoft limited-access approval per subscription.
      // Uncomment once approved.
      // {
      //   name: 'gpt-image-1'
      //   model: { format: 'OpenAI', name: 'gpt-image-1', version: '2025-04-15' }
      //   sku:   { name: 'GlobalStandard', capacity: 1 }
      // }
      // {
      //   name: 'gpt-image-1-5'
      //   model: { format: 'OpenAI', name: 'gpt-image-1.5', version: '2025-12-16' }
      //   sku:   { name: 'GlobalStandard', capacity: 1 }
      // }
    ]
  }
}
