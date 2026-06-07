# Feature Spec: 005 — Fix secondary Foundry RBAC collision

**Branch**: `005-fix-foundry2-rbac` | **Date**: 2026-06-07
**Predecessor**: `specs/004-eastus-image-foundry/`
**Constitution**: v1.2.0

## Background

Feature 004 deployed a second Foundry account in eastus. The merge to
`main` triggered `deploy.yml`, which ran `az deployment sub create`
against dev. The deploy **created the eastus account and the
MAI-Image-2.5 deployment successfully**, then failed on the role
assignment `ra-mi-aif2`:

```
RoleAssignmentExists: "The role assignment already exists. The ID of the
existing role assignment is fe8e3cbb349c58d2b4b66810b7c64fda."
```

## Root cause

`infra/modules/role-assignment/main.bicep` always assigns at
`scope: resourceGroup()`. The `scopeResourceId` field only feeds the
deterministic assignment **name** via
`guid(scopeResourceId, principalId, roleDefId)` — it does **not** narrow
the actual scope. Azure RBAC deduplicates by **(scope, principalId,
roleDefinitionId)**, not by name.

Therefore:
- `raFoundry` grants the workload MI `Cognitive Services User` at **RG
  scope** — which already covers every Cognitive Services account in the
  RG, including the new eastus account.
- `raFoundry2` requested the **same** (MI, Cognitive Services User, RG)
  tuple under a different name → `RoleAssignmentExists` at create time.

This passed `validate` and `what-if` because RBAC duplicate detection
happens during `create`, not preflight. (The pre-existing `raKv`/`raSt`/
`raSrch` never collided only because each uses a *different* role.)

## Fix

Remove the `raFoundry2` module entirely. The eastus account inherits
`Cognitive Services User` from the RG-scoped `raFoundry` grant, so the
workload identity can still do inference against it — no permission is
lost.

## Acceptance Criteria

1. `raFoundry2` removed from `infra/workload.bicep`.
2. `bicep build` + `lint` clean (no unused-symbol error: `foundry2` is
   still referenced by `diagFoundry2` + outputs).
3. `az deployment sub create` (dev) completes successfully and is
   idempotent on re-run.
4. The workload MI retains `Cognitive Services User` over the eastus
   account (via the RG-scoped assignment).

## Out of Scope

- Re-scoping the `role-assignment` module to honor `scopeResourceId`
  (would be a larger change affecting all callers; not needed here).
- Any change to the eastus account, its project, or MAI-Image-2.5 (all
  deployed successfully in 004).

## Constitution Compliance

- **I (Idempotent)**: this fix makes the template idempotent again
  (the collision was the only non-idempotent element).
- **IV / V / VI / VIII**: unchanged from 004; this is a pure removal.
