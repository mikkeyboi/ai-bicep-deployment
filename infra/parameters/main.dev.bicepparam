// infra/parameters/main.dev.bicepparam
// Default development environment.
// Region: eastus2 - broadest first-party Azure OpenAI surface (GPT-5,
// GPT-4o, embeddings, image-gen with limited-access approval).
// Model versions/SKUs verified via `az cognitiveservices model list --location eastus2`.
//
// Constitution v1.2.0: AI Foundry uses the unified Foundry resource
// (Microsoft.CognitiveServices kind=AIServices). Models live on the
// Foundry account itself; the standalone OpenAI account from feature
// 001 has been decommissioned.
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
  // Azure AI Search disabled for dev: eastus2 is currently returning
  // InsufficientResourcesAvailable for new Search services (regional
  // capacity, not a quota issue). Re-enable when capacity recovers, or
  // pin Search to an alternate region.
  enableAiSearch: false
  // Matrix homeserver (feature 003). Hostname sourced at compile time
  // from $env:MATRIX_HOSTNAME; MUST NOT be hardcoded (Constitution II).
  // Matrix homeserver (feature 003). VNet + delegated subnet provisioned
  // automatically by infra/modules/network when this is true.
  enableMatrix: true
  matrix: {
    hostname: readEnvironmentVariable('MATRIX_HOSTNAME', '')
    continuwuityImage: 'forgejo.ellis.link/continuwuation/continuwuity:v0.5.5'
    cloudflaredImage: 'docker.io/cloudflare/cloudflared:2026.3.0'
    // Cloudflared sidecar enabled; token sourced from KV secret
    // 'cloudflare-tunnel-token' via UAMI secret reference.
    enableCloudflareTunnel: true
    minReplicas: 1
    maxReplicas: 1
    homeserverCpu: '0.5'
    homeserverMemory: '1Gi'
    cloudflaredCpu: '0.25'
    cloudflaredMemory: '0.5Gi'
    shareQuotaGiB: 5
  }
  foundry: {
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
    ]
  }
  // Secondary Foundry account (feature 004): a SECOND AIServices account
  // in eastus, because the requested image models are NOT available in the
  // primary eastus2 region. Models attach to the account (single-region),
  // so an eastus account is required — a project alone cannot change region.
  //
  // API-key (local) auth is RE-ENABLED on THIS account only
  // (disableLocalAuth: false); the primary eastus2 account stays Entra-only.
  // See specs/004-eastus-image-foundry/plan.md Complexity Tracking for the
  // Security-section deviation rationale. Keys are NEVER committed — fetch at
  // runtime via `az cognitiveservices account keys list -n <acct> -g <rg>`.
  //
  // VERIFY before deploy (az/bicep not installed in authoring env):
  //   az cognitiveservices model list --location eastus \
  //     --query "[?contains(['gpt-image-2','MAI-Image-2.5'], model.name)].{name:model.name,format:model.format,version:model.version,sku:model.skus[0].name}" -o table
  // gpt-image-2 uses version 'latest' (module maps 'latest' -> null so Azure
  // picks the current GA version); pin an explicit date once confirmed.
  secondaryFoundry: {
    enabled: true
    location: 'eastus'
    disableLocalAuth: false   // API keys re-enabled on the eastus account only
    deployments: [
      {
        name: 'gpt-image-2'
        model: { format: 'OpenAI', name: 'gpt-image-2', version: 'latest' }
        sku:   { name: 'GlobalStandard', capacity: 1 }
      }
      {
        name: 'mai-image-2-5'
        model: { format: 'Microsoft', name: 'MAI-Image-2.5', version: '2026-06-02' }
        sku:   { name: 'GlobalStandard', capacity: 1 }
      }
    ]
  }
}
