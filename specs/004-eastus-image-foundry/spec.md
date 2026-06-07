# Feature Spec: 004 — East US Image Foundry (secondary account)

**Branch**: `004-eastus-image-foundry` | **Date**: 2026-06-06
**Predecessor**: `specs/002-new-foundry/`
**Constitution**: v1.2.0

## Background

The primary Foundry account (feature 002) lives in **eastus2**. Two
image models the operator wants are **not available in eastus2**:

- **`gpt-image-2`** (OpenAI, GA in Microsoft Foundry May 2026).
- **`MAI-Image-2.5`** (Microsoft MAI, `format=Microsoft`, sold directly
  by Azure; global-standard regions are West Central US, **East US**,
  West US, West Europe, Sweden Central, South India, UAE North — and
  explicitly NOT eastus2).

In the unified Foundry resource model, **model deployments attach to the
account** (`Microsoft.CognitiveServices/accounts` kind=`AIServices`),
and an account is **single-region**. A child `projects` resource is
co-located with its parent account and cannot independently change
region or host models. Therefore the eastus-only models require a
**second Foundry account in eastus**, with its own child project — not
merely a new project under the existing eastus2 account.

## User Story

> As the operator, I want a second Foundry project in **East US** that
> hosts `gpt-image-2` and `MAI-Image-2.5`, so I can deploy image models
> that are unavailable in my primary eastus2 region. I also want
> **API-key authentication re-enabled** on that East US account so I can
> call the image APIs with an `api-key` header during early
> experimentation.

## Acceptance Criteria

1. A second `Microsoft.CognitiveServices/accounts` kind=`AIServices`
   account is deployed in **eastus**, additive — the existing eastus2
   account and its deployments are unchanged.
2. The eastus account has `allowProjectManagement=true`, system-assigned
   identity, custom subdomain, and a child
   `Microsoft.CognitiveServices/accounts/projects` resource visible in
   the Foundry portal.
3. Two model deployments are attached to the eastus account:
   - `gpt-image-2` (format=`OpenAI`, `GlobalStandard`).
   - `MAI-Image-2.5` (format=`Microsoft`, version `2026-06-02`,
     `GlobalStandard`).

   > **Status (2026-06-07):** `gpt-image-2` is **deferred** — the dev
   > subscription returned `SpecialFeatureOrQuotaIdRequired` ("does not
   > have access to this model 'gpt-image-2,Version:2026-04-21'") at
   > preflight. That is a limited-access **registration** gate
   > (`aka.ms/oai/access`), not a region or quota-conflict issue. eastus
   > supports the model, so it stays in `region-capabilities.bicep`; only
   > the dev paramfile deployment is commented out until access is
   > granted. `MAI-Image-2.5` deploys now.
4. **API-key (local) auth is re-enabled on the eastus account only**
   (`disableLocalAuth=false`). The primary eastus2 account remains
   Entra-only (`disableLocalAuth=true`).
5. The region-capability gate validates the eastus models against the
   **eastus** region (not eastus2), and fails the deployment with a
   clear message if a model/region pair is unsupported.
6. RBAC: the workload UAMI is granted `Cognitive Services User` on the
   new eastus account (same least-privilege role as the eastus2 account).
7. Diagnostic settings on the eastus account route to the existing Log
   Analytics workspace.
8. No `listKeys()` output anywhere; no tenant/subscription/object IDs or
   keys in source. `bicep lint`, `bicep build`, `az deployment sub
   validate`, `what-if`, gitleaks all pass.

## Out of Scope

- Putting image models on the eastus2 account (region-incompatible).
- Re-enabling keys on the eastus2 account (stays Entra-only).
- test/prod parameter rollout (dev only in this feature; the
  `secondaryFoundry` field is optional, so test/prod compile unchanged).
- Storing or rotating the API keys (operator fetches at runtime; a
  future feature may persist them to Key Vault).

## Constitution Compliance

- **II (No Secrets/IDs)**: keys are never emitted or committed; fetched
  at runtime via `az cognitiveservices account keys list`.
- **IV (Modular / no hardcoded literals)**: reuses the existing
  `foundry-account` module unchanged; region, SKUs, model names, and the
  `disableLocalAuth` toggle all flow from the dev paramfile.
- **V (Naming)**: the eastus account name embeds the `eus` region short
  code via the existing `foundry()`/`project()` helpers, so it never
  collides with the eastus2 (`eus2`) account.
- **VI (Validation Gates)**: lint/build/validate/what-if/gitleaks.
- **VIII (Consumption Billing)**: both `gpt-image-2` (Azure OpenAI) and
  `MAI-Image-2.5` (Microsoft MAI) are **sold directly by Azure** and bill
  as Azure consumption — not Marketplace SaaS. Compliant.
- **Security section deviation**: "managed identity over keys" is
  intentionally relaxed for the eastus account (keys re-enabled). Logged
  in `plan.md` → Complexity Tracking, as required by Governance.
