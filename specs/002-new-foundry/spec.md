# Feature Spec: 002 — New Foundry Resource

**Branch**: `002-new-foundry` | **Date**: 2026-05-10
**Predecessor**: `specs/001-aio-foundation/`
**Constitution**: v1.2.0

## Background

Feature 001 deployed AI Foundry as a hub workspace + project workspace
(`Microsoft.MachineLearningServices/workspaces` kind=`Hub`/`Project`).
Microsoft has since shipped the **new Foundry portal** experience that
is built on the **unified Foundry resource**:
`Microsoft.CognitiveServices/accounts` kind=`AIServices` with
child `Microsoft.CognitiveServices/accounts/projects`. Hub-based
workspaces are not surfaced by the new portal.

## User Story

> As the operator, I want a single Foundry resource with native
> projects so the new Foundry portal experience works against my
> dev environment, and so model deployments live on the Foundry
> account itself instead of a sidecar OpenAI account.

## Acceptance Criteria

1. `infra/main.bicep` deploys a `Microsoft.CognitiveServices/accounts`
   kind=`AIServices` resource with `allowProjectManagement=true`,
   system-assigned identity, custom subdomain, `disableLocalAuth=true`.
2. A child `Microsoft.CognitiveServices/accounts/projects` resource is
   created and visible in the new Foundry portal.
3. Chat + embedding model deployments are attached **directly** to the
   Foundry account (not to a separate OpenAI account).
4. The standalone `Microsoft.CognitiveServices/accounts` kind=`OpenAI`
   account from feature 001 is decommissioned (deleted + purged).
5. Old hub + project workspaces are deleted from the resource group.
6. Storage, Key Vault, AI Search (when enabled), Log Analytics,
   App Insights, UAMI are reused as-is.
7. RBAC: workload UAMI is granted `Cognitive Services User` on the
   new Foundry account.
8. `bicep lint`, `bicep build`, `az deployment sub validate`,
   `what-if`, gitleaks all pass before deploy.

## Out of Scope

- Multi-region deployment.
- Connections from the Foundry account to external resources
  (deferred until needed).
- Test/prod parameter file rollout (handled in a follow-up).

## Constitution Compliance

- **VIII (Consumption Billing)**: `Microsoft.CognitiveServices` kind=
  `AIServices` and child `projects`/`deployments` bill as Azure
  consumption — same RP family as the previous OpenAI account.
- **IV (Modular)**: new `infra/modules/foundry-account/` module
  (account + project) replaces `foundry-{hub,project,connection}`.
- **V (Naming)**: account uses `aif-…` abbreviation; project uses
  `proj-…` (existing helper).
