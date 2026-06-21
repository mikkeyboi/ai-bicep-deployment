# Feature 011: Pin the auto-attached Container Registry on the ML workspace

**Branch**: `011-ml-acr-pin` | **Constitution**: v1.2.0
**Follows**: 007/008/009 (ML workspace + compute), 010 (GPU cluster).

## Problem

After 010 merged, the `deploy.yml` run failed at the `ml-ws` step:

```
BadRequest: Detaching Container Registry with workspace is not supported
```

Cause: AzureML **auto-creates and attaches** a Container Registry to the
workspace the first time a job builds an environment image. The mechinterp
`mlplatform` pipeline triggered that build, so `mlw-aio-dev-eus2` now has an ACR
(`51119126436640639d290bc8189dcbbf`) attached. The IaC `workspace.bicep`
declares no `containerRegistry`, so every redeploy computes a diff (live has an
ACR, template wants none) and tries to **detach** it. Azure forbids detaching an
ACR from a workspace, so the deploy fails.

This is independent of the 010 GPU cluster — it is a latent gap that the first
image build exposed: the template stopped matching live state.

## Decision

**Pin the auto-attached ACR in the template so it matches live state.**

- `workspace.bicep` gains an optional `containerRegistryName` param. When set,
  the module composes the ACR resource id with `resourceId()` and sets
  `properties.containerRegistry`; when empty it stays `null` (pre-first-build
  behaviour, unchanged for test/prod).
- `machineLearningConfig` gains an optional `containerRegistryName: string?`.
- The dev paramfile sets it to the auto-created name.

Passing the **name** (not the full id) and composing the id in-module keeps the
subscription GUID out of source (Constitution II) — the name is an opaque hex
string with no identifiers.

## Change

- `infra/modules/machine-learning/workspace.bicep`: `+ param containerRegistryName`,
  compose id via `resourceId()`, set `properties.containerRegistry`.
- `infra/shared/types.bicep`: `+ containerRegistryName: string?` on `machineLearningConfig`.
- `infra/workload.bicep`: pass `containerRegistryName` through to `mlWs`.
- `infra/parameters/main.dev.bicepparam`: set the auto-created ACR name.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| II — no secrets/IDs in source | PASS | ACR **name** only (opaque hex, no sub GUID); id composed in-module via `resourceId()`. |
| IV — no hardcoded SKU/region/id in modules | PASS | The module takes a name param; the literal lives only in the dev paramfile. |
| V — names from naming.bicep | N/A | The ACR is AzureML-managed (auto-named), not a resource this stack names; we only reference an existing one. |
| VIII — consumption-only | PASS | No new billable resource; references an existing auto-created ACR. |

No Complexity Tracking entries — no deviation introduced.

## Acceptance

- `bicep build` exits 0; `build-params` dev/test/prod all succeed (test/prod omit
  `machineLearning`, so the optional field must stay back-compat). **Verified: all 0.**
- Compiled `main.json` sets `containerRegistry` on the workspace from the param.
- On deploy, the `ml-ws` step succeeds (template now matches the attached ACR;
  no detach attempted).

## Compute identity for keyless-datastore reads

Same deploy, related fix. An AmlCompute job reading a keyless datastore (the
mechinterp `trials_datalake`) authenticates as the **cluster's own MSI**, not the
workspace MSI; without one the run fails `Identity of the specified managed
compute ... is not found`. So:

- `compute.bicep`: clusters get `identity: { type: 'SystemAssigned' }` and output
  `computeClusterPrincipalIds`.
- `workload.bicep`: one `Storage Blob Data Contributor` grant per cluster MSI on
  the shared storage account, created after `ml-compute` (`dependsOn`). Different
  principal+name than `raMlBlob`, so no `RoleAssignmentExists` collision.

The operator-user storage grant (needed to upload job code) stays a manual step —
it is a per-developer grant, not infra.

## Out of scope

- The compute instance (deferred, feature 009) and the GPU cluster shape (010)
  are unchanged.
