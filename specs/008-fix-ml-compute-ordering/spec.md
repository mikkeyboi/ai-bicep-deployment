# Feature 008: Fix ML compute provisioning order (StorageMountError)

**Branch**: `008-fix-ml-compute-ordering` | **Constitution**: v1.2.0
**Fixes**: the deploy failure from feature 007's first merge.

## Problem

The first dev deploy of feature 007 failed. Redacted error from
`az deployment sub create`:

```
ResourceDeploymentFailure → .../computes/ci-aio-dev-eus2-cpu
StorageMountError: "The specified Azure ML Compute Instance
  ci-aio-dev-eus2-cpu setup failed ... Failed to mount storage.
  Hint: Miss required permission Storage File Data Privileged
  Contributor, please find your admin to assign the permission to
  <workspace-MSI-objectId>. Please delete and try to recreate."
```

## Root cause (a Bicep ordering bug)

A keyless **ComputeInstance** mounts `workspacefilestore` via the
**workspace's system-assigned MSI during its own provisioning**. So the
`Storage File Data Privileged Contributor` role assignment must already
exist when the instance is created.

In feature 007 the workspace **and** its computes were created together
inside one module (`modules/machine-learning/main.bicep`), while the three
ML role assignments lived in `workload.bicep` and depended on that
module's output (`ml.outputs.principalId`). ARM therefore scheduled the
roles **after** the module — i.e. after the compute instance. The
instance raced the file-role grant, the mount was denied, and the
instance reached a terminal `Failed` state. (The cluster at `minNodes: 0`
mounts nothing at create, so it was not the trigger.)

A `dependsOn` alone could not fix it: the computes were inside the same
module whose output the roles consume, which would be a cycle.

## Fix

Split the one module into two so the caller can sequence them around the
RBAC grants:

```
modules/machine-learning/
  main.bicep      [DELETED]
  workspace.bicep [NEW]  — the workspace only (emits principalId)
  compute.bicep   [NEW]  — instances + clusters; references the workspace
                            as `existing`
```

`workload.bicep` now wires the explicit order:

```
mlWs (workspace)
  → raMlBlob / raMlFile / raMlKv   (workspace MSI storage + KV roles)
    → mlCompute  (dependsOn: [ mlWs, raMlBlob, raMlFile, raMlKv ])
```

The `mlCompute` module's `dependsOn` on the role assignments guarantees
the file-mount permission exists before any ComputeInstance provisions.
Verified in compiled ARM: `ml-compute.dependsOn` = [mlWs, raMlBlob,
raMlFile, raMlKv].

## Cleanup required before re-deploy

The first deploy left `ci-aio-dev-eus2-cpu` in a terminal `Failed`
state, and a Failed ComputeInstance **cannot be updated in place** — it
must be **deleted** first (per the BatchAI hint). The workspace and (if
present) the cluster are fine to keep; ARM is incremental.

```bash
# Delete only the failed compute instance, then re-deploy:
az ml compute delete --name ci-aio-dev-eus2-cpu \
  --workspace-name mlw-aio-dev-eus2 --resource-group rg-aio-dev-eus2 --yes
```

The re-deploy (merge → deploy.yml, or local wrapper) recreates the
instance after the roles are in place. ARM role assignments are
idempotent (deterministic GUID names), so re-running is safe even if some
grants already landed.

## Constitution Check (v1.2.0)

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Pure Bicep; deterministic names; explicit dependsOn for correct order. |
| II. No Secrets / IDs / PII | PASS | No new GUIDs/keys; no listKeys(). |
| IV. Modular / Single Entry | PASS | Two focused modules replace one; typed I/O; names still from shared/naming. |
| V. Naming & Tagging | PASS | Unchanged names (`mlw-`/`ci-`/`cc-`). |
| VI. Validation Gates | PASS | lint + build + build-params(×3) clean; validate/what-if/gitleaks in CI. |
| VII. Environment Parity | PASS | `machineLearning` still optional; test/prod unaffected. |

No Complexity Tracking entries (no posture deviation introduced).
