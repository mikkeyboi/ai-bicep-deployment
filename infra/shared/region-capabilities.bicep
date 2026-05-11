// infra/shared/region-capabilities.bicep
// Compile-time-ish guard for model availability per region. Bicep does
// not (as of CLI 0.43) support an `assert` keyword, so this module
// exposes a boolean check function. Callers MUST guard model deployments
// behind it; if a (region, format, name) pair is unsupported the
// returned false should be turned into an explicit deployment failure
// in main.bicep using a deliberate error condition.

metadata description = 'Static region-capability map for first-party Azure OpenAI model availability. Anthropic / partner Marketplace models are excluded by Constitution VIII (v1.1.0).'

// Supported pairs: location -> set of "<format>:<name>" entries.
// Verified 2026-05-10 via `az cognitiveservices model list --location <loc>`.
// Only first-party (`format = 'OpenAI'`) entries appear here; partner /
// Marketplace formats are forbidden by Constitution Principle VIII.
@export()
var supported = {
  eastus2: [
    // OpenAI text / embedding (Standard SKU available; GlobalStandard varies)
    'OpenAI:gpt-5-chat'
    'OpenAI:gpt-4.1'
    'OpenAI:gpt-4.1-mini'
    'OpenAI:gpt-4o'
    'OpenAI:gpt-4o-mini'
    'OpenAI:text-embedding-3-large'
    'OpenAI:text-embedding-3-small'
    // OpenAI image (limited access; parameter-only / disabled by default)
    'OpenAI:gpt-image-1'
    'OpenAI:gpt-image-1.5'
  ]
  swedencentral: [
    'OpenAI:gpt-4o'
    'OpenAI:text-embedding-3-large'
  ]
  canadacentral: [
    'OpenAI:gpt-4o'
    'OpenAI:gpt-4o-mini'
    'OpenAI:text-embedding-3-large'
    'OpenAI:text-embedding-3-small'
  ]
}

@export()
@description('Returns true iff a (location, format, name) triple is in the supported map.')
func isSupported(location string, format string, name string) bool =>
  contains(supported, location) && contains(supported[location], '${format}:${name}')

@export()
@description('Build the diagnostic message for a missing model.')
func missingMessage(location string, format string, name string) string =>
  'Model "${format}:${name}" is not in the region-capability map for "${location}". Update infra/shared/region-capabilities.bicep after verifying with `az cognitiveservices model list --location ${location}`.'
