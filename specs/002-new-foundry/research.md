# Research: 002 New Foundry

## D1. Resource model

**Decision**: use `Microsoft.CognitiveServices/accounts` kind=
`AIServices` (the "Foundry account") with child
`Microsoft.CognitiveServices/accounts/projects`.

**Why**: the new Foundry portal (ai.azure.com — "new resource provider"
toggle) only enumerates projects backed by this resource model.
Hub-based ML workspaces (`Microsoft.MachineLearningServices/workspaces`
kind=`Hub`/`Project`) are now legacy for AI Foundry consumption.

**API version**: `2025-04-01-preview` (also valid: `2025-06-01` GA for
the parent `accounts` resource; `projects` requires the
`2025-04-01-preview` API surface). We use `2025-04-01-preview` for
both account + projects + deployments to stay on a single, consistent
API surface that supports `allowProjectManagement` and the project
sub-resource.

## D2. AVM availability

The Azure Verified Module
`avm/res/cognitive-services/account` predates the new project
sub-resource (tracked by [bicep-registry-modules#5319](https://github.com/Azure/bicep-registry-modules/issues/5319)).
We therefore author a small first-party module rather than wrapping
AVM, until the AVM module ships first-class project support.

## D3. Models on Foundry vs. sidecar OpenAI account

**Decision**: deploy chat + embedding models **directly on the new
Foundry AIServices account** and **decommission** the standalone
`oai-aio-dev-eus2-npnga` (kind=OpenAI) account.

**Why**:
- The new Foundry portal expects models discoverable on the same
  account that backs the project.
- Avoids a redundant Cognitive Services account and its quota
  bookkeeping.
- Simpler RBAC (one principal-scope: Cognitive Services User on the
  Foundry account is sufficient for Azure OpenAI inference because
  `kind=AIServices` is a superset that hosts OpenAI deployments).

The previous standalone OpenAI account is **deleted and purged** so
the name frees up; the Foundry account uses `aif-aio-dev-eus2-<hash>`.

## D4. Project capabilityHostKind

The `projects` sub-resource in `2025-04-01-preview` does not require a
`capabilityHost` for vanilla "AI Foundry" usage. Capability hosts
(`Agents`, `OpenAI`) are only needed for the Agent Service / threaded
agents — not in scope for 002.

## D5. Connections

Skipped. The previous `foundry-connection` module wired the Hub to the
sidecar OpenAI account. With models living on the Foundry account
itself, no connection is required for chat/embedding inference.

## D6. RBAC

The workload UAMI receives `Cognitive Services User`
(`a97b65f3-24c7-4388-baec-2e87135dc908`) on the Foundry account. This
role permits Azure OpenAI data-plane reads (inference). The account's
own system-assigned identity remains for outbound storage/KV access if
ever needed (none in 002).

## D7. Old hub teardown

`Microsoft.MachineLearningServices/workspaces` kind=Hub holds child
Project workspaces, role assignments, and diagnostic settings. We
delete in order:
1. Project workspace (`proj-aio-dev-eus2`)
2. Hub workspace (`hub-aio-dev-eus2`)
Then delete + purge the standalone OpenAI account
(`oai-aio-dev-eus2-npnga`) to free the name.
