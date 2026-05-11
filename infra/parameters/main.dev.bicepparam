// infra/parameters/main.dev.bicepparam
// Default development environment.
// Region: eastus2 — broadest first-party Azure OpenAI surface (GPT-5,
// GPT-4o, embeddings, image-gen with limited-access approval).
// Model versions/SKUs verified via `az cognitiveservices model list --location eastus2`.
//
// NOTE: gpt-4o, gpt-4.1 and text-embedding-3-large are deployed as
// 'Standard' in eastus2 (where this subscription has TPM quota).
// gpt-5-chat (GlobalStandard) is held in test/prod paramfiles pending a
// quota request; dev uses gpt-4.1 as the primary chat model meanwhile.
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
  // Azure AI Search disabled for dev until eastus2 capacity recovers.
  // 2026-05-10: srch deploy returned InsufficientResourcesAvailable on the
  // entire region's Search SKU pool. Re-enable once capacity opens or pick
  // an alternate region. test/prod paramfiles keep Search enabled.
  enableAiSearch: false
  openAi: {
    enabled: true
    deployments: [
      {
        name: 'gpt-4-1'
        model: { format: 'OpenAI', name: 'gpt-4.1', version: '2025-04-14' }
        sku:   { name: 'Standard', capacity: 50 }
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
