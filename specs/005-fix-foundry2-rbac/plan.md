# Implementation Plan: 005 Fix secondary Foundry RBAC collision

**Branch**: `005-fix-foundry2-rbac` | **Date**: 2026-06-07
**Spec**: [spec.md](./spec.md) | **Constitution**: v1.2.0

## Summary

Remove the redundant `raFoundry2` role-assignment module from
`infra/workload.bicep`. The shared `role-assignment` module assigns at
RG scope, so the existing `raFoundry` grant already covers the eastus
account; the duplicate (principal, role, RG-scope) tuple failed the
`create` step with `RoleAssignmentExists`. Pure removal — no other
behavior changes.

## Directory Diff

```
infra/
  workload.bicep              [MODIFIED] remove raFoundry2 (replaced by explanatory comment)
specs/005-fix-foundry2-rbac/  [NEW]
```

## Constitution Check (v1.2.0)

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Removes the only non-idempotent element; re-deploy now clean. |
| II. No Secrets / IDs / PII | PASS | No identifiers touched. |
| III. OIDC-First | PASS | No CI auth change. |
| IV. Modular / Single Entry | PASS | Removal only; no new literals. |
| V. Naming & Tagging | PASS | Unchanged. |
| VI. Validation Gates | PASS | build/lint verified locally; validate/what-if/gitleaks in CI. |
| VII. Environment Parity | PASS | Applies to all envs that set `secondaryFoundry`; dev only today. |
| VIII. Consumption Billing | PASS | Unchanged. |

## Verification (post-merge deploy state, confirmed via az 2026-06-07)

Before the fix, the failed deploy left a correct partial state:
- eastus account `aif-aio-dev-eus-npnga`: `Succeeded`,
  `disableLocalAuth=false` (API keys on), `publicNetworkAccess=Enabled`.
- eastus deployment `mai-image-2-5` (MAI-Image-2.5, 2026-06-02,
  GlobalStandard): `Succeeded`.
- eastus2 account + its 5 deployments (incl. the operator's manual
  `gpt-image-2` and `sora-2`): untouched, all `Succeeded`.

So only the RBAC step needs to clear. Because ARM deploys are
incremental and role assignments are idempotent by
guid(scope,principal,role), re-running after this removal completes
cleanly (the eastus account already exists; MAI already deployed; the
RG-scoped `raFoundry` already present).

## Phases

- **Phase 0**: Spec + plan (this directory).
- **Phase 1**: Remove `raFoundry2` (done).
- **Phase 2**: build + lint (local), validate + what-if + gitleaks (CI).
- **Phase 3**: merge → `deploy.yml` re-runs → confirm SUCCESS.
