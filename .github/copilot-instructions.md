# Copilot / Agent Instructions — ai-bicep-deployment

Source of truth: `.specify/memory/constitution.md`. These instructions
are a short operational mirror; if they ever conflict with the
constitution, the constitution wins.

## Hard rules

1. **No identifiers in source.** Never write any Azure tenant ID,
   subscription ID, object ID, principal ID, API key, connection string,
   or personal email/name into any tracked file. Use placeholders
   (`<YOUR_TENANT_ID>`) in docs and parameters; real values come from
   GitHub Variables (CI) or local shell args (operator).
2. **OIDC only for CI.** No client secrets. The `azure/login@v2` action
   reads `vars.AZURE_TENANT_ID`, `vars.AZURE_SUBSCRIPTION_ID`,
   `vars.AZURE_CLIENT_ID` from the GitHub Environment.
3. **Modular Bicep.** One subscription-scope `infra/main.bicep`. Every
   resource family lives in its own module under `infra/modules/<m>/`
   with typed inputs and key-free outputs. Naming and tagging come from
   `infra/shared/naming.bicep` and `infra/shared/tags.bicep` —
   modules MUST NOT construct names or tag maps locally.
4. **Never echo `listKeys()` output.** Outputs return resource IDs,
   endpoints, and (where Microsoft documents them as non-secret)
   connection strings. Anything secret stays in Key Vault and is read
   by the workload at runtime via managed identity.
5. **Always `what-if` before `create`.** Both CI and the local script
   run `validate` → `what-if` → (gate) → `create`.
6. **Spec-driven.** Changes to `infra/` require a spec under
   `specs/NNN-*/`. Update `tasks.md` as work progresses; do not skip
   the plan/research/data-model artifacts.
7. **Conventional Commits.** Scopes: `infra`, `ci`, `docs`, `spec`,
   `scripts`. Squash-merge to `main`.

## When generating code

- Prefer Azure Verified Modules (`br/public:avm/res/...`) over
  hand-rolled resources where a stable AVM exists; otherwise hand-roll
  a minimal module that meets the contract in
  `specs/001-aio-foundation/contracts/modules.contract.md`.
- Parameters use the user-defined types in `infra/shared/types.bicep`.
- Region/SKU/model literals only ever appear in
  `infra/parameters/main.<env>.bicepparam`.
- Tag every taggable resource with `tags(...)` from
  `infra/shared/tags.bicep`.
- Idempotent role assignment names: `guid(scope, principalId, roleDefinitionId)`.

## When asked to deploy or run Azure commands

- Use the operator's local `az login` context. Confirm it matches the
  requested subscription/tenant before any state-changing call.
- Prefer the wrappers `scripts/deploy.ps1` / `scripts/deploy.sh` over
  raw `az deployment sub create`.

## Forbidden phrases in any committed file

The enumerated forbidden literals are codified in `.gitleaks.toml`
(rules `azure-tenant-id-literal`, `azure-subscription-id-literal`,
`operator-email-1`, `operator-email-2`). Do not commit:

- The operator's Entra tenant GUID or Azure subscription GUID.
- The operator's personal email addresses (gmail).
- Any literal `client_secret`, `accessKey`, `connectionString`-with-key,
  Cognitive Services / OpenAI key (32-hex), or SAS token.
