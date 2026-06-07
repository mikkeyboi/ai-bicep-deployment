# Implementation Plan: 004 East US Image Foundry

**Branch**: `004-eastus-image-foundry` | **Date**: 2026-06-06
**Spec**: [spec.md](./spec.md) | **Constitution**: v1.2.0

## Summary

Add an **optional second Foundry (AIServices) account in eastus**,
additive to the primary eastus2 account, to host two image models that
eastus2 does not offer (`gpt-image-2`, `MAI-Image-2.5`). Re-enable
API-key (local) auth on the eastus account only. No existing resource
changes shape; the new account is gated behind an optional
`secondaryFoundry` config block so test/prod (which omit it) compile and
deploy unchanged.

## Directory Diff

```
infra/
  shared/
    types.bicep                 [MODIFIED] modelFormat += 'Microsoft';
                                 foundryAccountConfig += location?, disableLocalAuth?;
                                 environmentConfig += secondaryFoundry?
    region-capabilities.bicep   [MODIFIED] add eastus block (gpt-image-2, MAI-Image-2.5, + text)
  workload.bicep                [MODIFIED] secondary account+project+RBAC+diagnostics+outputs
  main.bicep                    [MODIFIED] capability gate validates secondary region; outputs
  parameters/main.dev.bicepparam [MODIFIED] add secondaryFoundry block (eastus, 2 image models)
  modules/foundry-account/*     [UNCHANGED] reused as-is (already supports disableLocalAuth + format passthrough)

specs/004-eastus-image-foundry/ [NEW]
```

No new module is required: `foundry-account/main.bicep` already exposes
a `disableLocalAuth` parameter and passes `model.format` straight
through, so it serves both accounts.

## Constitution Check (v1.2.0)

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Pure Bicep; what-if before create; account name is deterministic. |
| II. No Secrets / IDs / PII | PASS | No listKeys() added; keys fetched at runtime; no GUIDs/emails in source. |
| III. OIDC-First | PASS | No CI auth changes. |
| IV. Modular / Single Entry | PASS | Reuses existing module; region/SKU/model/auth literals only in the dev paramfile. |
| V. Naming & Tagging | PASS | eastus account uses `aif-…-eus-…`; never collides with `…-eus2-…`. |
| VI. Validation Gates | PASS | lint + build verified locally (exit 0); validate/what-if/gitleaks in CI. |
| VII. Environment Parity | PASS | `secondaryFoundry` is optional; test/prod omit it and are unaffected. |
| VIII. Consumption Billing | PASS | gpt-image-2 (Azure OpenAI) + MAI-Image-2.5 (Microsoft MAI) are sold directly by Azure. |

## Complexity Tracking

| Deviation | Principle / Section | Why it is necessary | Mitigation |
|---|---|---|---|
| **API-key (local) auth re-enabled** on the eastus account (`disableLocalAuth=false`). | Security & Compliance → "Managed identity over keys for all service-to-service auth where the resource supports it." | Operator explicitly requested key auth for early image-API experimentation (the MAI/OpenAI image REST samples use an `api-key` header). | Scoped to the **eastus account only**; the primary eastus2 account stays Entra-only. Keys are never emitted as outputs (listKeys() still banned) nor committed; they are read at runtime via `az cognitiveservices account keys list`. UAMI is *also* granted `Cognitive Services User`, so Entra auth remains available in parallel and key auth can be turned back off (flip `disableLocalAuth` to true) with no other change. A follow-up can persist the key to Key Vault and re-disable local auth. |

## Phases

- **Phase 0**: Spec + plan + research + data-model + contracts + quickstart (this directory).
- **Phase 1**: Implement type/capability/workload/main/paramfile edits.
- **Phase 2**: Validate — bicep lint + build (done, exit 0), compiled-ARM presence checks, privacy grep, gitleaks (CI), `az ... model list --location eastus` region/version confirmation, validate + what-if (operator/CI).
- **Phase 3**: Deploy dev, smoke check (account show, deployment list, project list, a single image generation call).
- **Phase 4**: Merge + sanitized DEPLOY_REPORT_004.md.

## Pre-deploy verification (az/bicep not installed in authoring env)

```bash
# Confirm both models + exact versions/SKUs are live in eastus:
az cognitiveservices model list --location eastus \
  --query "[?contains(['gpt-image-2','MAI-Image-2.5'], name)].{name:name,format:format,version:version,sku:skus[0].name}" -o table
```

If `gpt-image-2` returns a specific dated version, pin it in the
paramfile in place of `'latest'`. If `MAI-Image-2.5` reports a version
other than `2026-06-02`, update the paramfile to match.
