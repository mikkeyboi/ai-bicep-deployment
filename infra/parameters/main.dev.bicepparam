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
    // Local auth (API keys) enabled for image-gen experimentation; keys
    // fetched at runtime, never committed. Entra ID still works alongside.
    disableLocalAuth: false
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
  // Secondary Foundry account (feature 004): a second AIServices account in
  // eastus for image models unavailable in eastus2. Models are single-region,
  // so a separate account (not just a project) is required. Local auth enabled
  // on this account only; see specs/004 plan.md for the security rationale.
  //
  // gpt-image-2 omitted: preflight returns SpecialFeatureOrQuotaIdRequired
  // (limited-access gate, aka.ms/oai/access — not quota). Re-add once granted:
  //     { name: 'gpt-image-2'
  //       model: { format: 'OpenAI', name: 'gpt-image-2', version: 'latest' }
  //       sku:   { name: 'GlobalStandard', capacity: 1 } }
  // It stays in region-capabilities.bicep (eastus supports it; sub isn't registered).
  secondaryFoundry: {
    enabled: true
    location: 'eastus'
    disableLocalAuth: false
    deployments: [
      {
        name: 'mai-image-2-5'
        model: { format: 'Microsoft', name: 'MAI-Image-2.5', version: '2026-06-02' }
        sku:   { name: 'GlobalStandard', capacity: 1 }
      }
    ]
  }
  // Azure Machine Learning (feature 007): a standard training workspace in
  // eastus2 (kind=Default — a real ML workspace, NOT a Foundry hub) plus a
  // CPU compute instance and a CPU compute cluster. Reuses the shared
  // storage / Key Vault / App Insights; datastores are keyless
  // (systemDatastoresAuthMode=identity).
  //
  // GPU-READY: the processor class ('cpu'/'gpu') is baked into each compute
  // name (ci-aio-dev-eus2-cpu, cc-aio-dev-eus2-cpu). To add GPU later, just
  // append an entry with processor:'gpu' and a GPU vmSize — the CPU targets
  // keep their names. Example (uncomment once GPU quota is approved):
  //   computeClusters: [
  //     { processor:'cpu', vmSize:'Standard_DS3_v2', vmPriority:'Dedicated'
  //       scale:{ minNodes:0, maxNodes:4, nodeIdleTimeBeforeScaleDown:'PT300S' } }
  //     { processor:'gpu', vmSize:'Standard_NC6s_v3', vmPriority:'Dedicated'
  //       scale:{ minNodes:0, maxNodes:2, nodeIdleTimeBeforeScaleDown:'PT300S' } }
  //   ]
  // A GPU box/cluster needs the matching NC/ND-series quota in eastus2
  // (request via the portal "Quotas" blade) before it will deploy.
  machineLearning: {
    enabled: true
    friendlyName: 'AIO dev ML workspace'
    // ACR pin (feature 011): AzureML auto-created + attached this Container
    // Registry on the first environment-image build (mlplatform pipeline).
    // An attached ACR cannot be detached, so a redeploy of a workspace declared
    // without one fails with "Detaching Container Registry with workspace is not
    // supported". Pinning the auto-created name here keeps the template aligned
    // with live state. Name is a hex string (no subscription GUID); the id is
    // composed in-module via resourceId() so the GUID stays out of source.
    containerRegistryName: '51119126436640639d290bc8189dcbbf'
    // computeInstances DEFERRED (feature 009): a keyless ComputeInstance
    // mounts workspacefilestore via the workspace MSI DURING create, and
    // that mount fails with StorageMountError until the 'Storage File Data
    // Privileged Contributor' grant has propagated to the storage DATA
    // plane — a gap ARM's natural ordering (~3.5 min) does not cover (3
    // consecutive deploys failed; see specs/009). The compute CLUSTER below
    // (minNodes:0) never mounts at create, so it deploys clean. Re-add the
    // instance once the file-datastore RBAC/propagation fix lands:
    //   computeInstances: [
    //     { processor:'cpu', vmSize:'Standard_DS3_v2', idleTimeBeforeShutdown:'PT30M' }
    //   ]
    computeInstances: []
    computeClusters: [
      {
        processor: 'cpu'
        vmSize: 'Standard_DS3_v2'
        vmPriority: 'Dedicated'
        scale: {
          minNodes: 0
          maxNodes: 4
          nodeIdleTimeBeforeScaleDown: 'PT300S'
        }
      }
      // GPU cluster (feature 010): low-priority Standard_NC6s_v3 (1x V100 16GB,
      // sm_70) for the mechinterp research runs. minNodes:0 => free when idle;
      // LowPriority => cheapest pre-emptible GPU (runs are restartable). The CPU
      // entry above is UNCHANGED, so cc-aio-dev-eus2-cpu is not replaced; this
      // adds cc-aio-dev-eus2-gpu. A cluster (min 0 nodes) does not mount
      // workspacefilestore at create, so it is not subject to the 009
      // StorageMountError. REQUIRES low-priority NCSv3 vCPU quota in eastus2
      // (6 vCPU/node x 2 = 12) — see specs/010 quota check before deploy.
      {
        processor: 'gpu'
        vmSize: 'Standard_NC6s_v3'
        vmPriority: 'LowPriority'
        scale: {
          minNodes: 0
          maxNodes: 2
          nodeIdleTimeBeforeScaleDown: 'PT300S'
        }
      }
    ]
  }
}
