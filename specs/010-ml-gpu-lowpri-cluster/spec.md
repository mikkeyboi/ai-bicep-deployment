# Feature 010: Low-priority GPU compute cluster for dev ML

**Branch**: `010-ml-gpu-lowpri-cluster` | **Constitution**: v1.2.0
**Follows**: 007 (added ML), 008 (fixed compute ordering), 009 (cluster-only dev-green).

## Problem

The dev ML workspace (`mlw-aio-dev-eus2`) has a CPU cluster
(`cc-aio-dev-eus2-cpu`, live since 009) but no GPU. The mechinterp research
line needs cloud GPU to (a) reproduce local RTX 5060 results on neutral
hardware and (b) run models larger than the laptop's 8 GB budget allows
(the local card cannot host anything past Gemma 3 1B without quantizing
activations, which the interpretability work forbids).

The work is restartable, batch-style activation capture + steering sweeps —
a textbook fit for **pre-emptible low-priority** GPU at a fraction of
dedicated cost.

## Decision

**Add one GPU cluster to the dev paramfile: a low-priority
`Standard_NC6s_v3`, scale-to-zero, max 2 nodes.**

- `Standard_NC6s_v3` = 1× NVIDIA V100 16 GB (Volta, sm_70). 16 GB comfortably
  hosts the small instruct models this research uses (Qwen2.5-1.5B, Gemma 3 1B)
  in bf16 with headroom for activation caches.
- `vmPriority: 'LowPriority'` — cheapest GPU; pre-emption is acceptable because
  every run is checkpointed/restartable and writes its result to the trials
  datalake on completion.
- `minNodes: 0` — the cluster costs **nothing** when idle (consumption posture,
  Constitution VIII). It scales up only while a job is queued.

This is a **pure paramfile change**. The 007 design deliberately made the
processor class (`cpu`/`gpu`) a naming-slot token and `vmPriority` an optional
cluster field, precisely so a GPU cluster is added by appending one entry with
**no rename** of the existing CPU cluster and **no module change**. We are
exercising that designed-in extension point, nothing more.

## Change

`infra/parameters/main.dev.bicepparam`, `machineLearning.computeClusters`:
append a second entry

```bicep
{
  processor: 'gpu'
  vmSize: 'Standard_NC6s_v3'
  vmPriority: 'LowPriority'
  scale: { minNodes: 0, maxNodes: 2, nodeIdleTimeBeforeScaleDown: 'PT300S' }
}
```

The CPU cluster entry is untouched, so `cc-aio-dev-eus2-cpu` is not replaced.
The new cluster is named `cc-aio-dev-eus2-gpu` by `naming.bicep`'s existing
`mlComputeCluster` helper (processor in the instance slot).

No new module, type, RBAC grant, or workspace change. The cluster
(`minNodeCount: 0`) does not mount `workspacefilestore` at create, so it is
**not** subject to the StorageMountError that defers the compute instance
(feature 009) — it deploys clean.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| II — no secrets/IDs in source | PASS | No identifiers added; SKU + priority are non-secret literals in the paramfile. |
| IV — no hardcoded SKU/region in modules | PASS | `Standard_NC6s_v3`/`LowPriority` live ONLY in the paramfile; the module/types already accept them generically. |
| V — names only from naming.bicep | PASS | `cc-aio-dev-eus2-gpu` resolved by `mlComputeCluster`; no literal name added. |
| VIII — consumption-only | PASS | `minNodes: 0` (free when idle) + LowPriority (cheapest). AmlCompute is consumption-billed; no Marketplace/partner offer. |

**No Complexity Tracking entries** — this change introduces no deviation from
the security/consumption posture.

## Pre-deploy quota check (REQUIRED before merge → deploy)

A GPU cluster needs **Low-Priority NC-series vCPU quota** in `eastus2` for the
subscription, distinct from dedicated quota and from the CPU family:

```bash
# Dedicated:
az vm list-usage -l eastus2 --query "[?contains(name.value,'NCSv3')]" -o table
# Low-priority (the relevant pool here):
az vm list-usage -l eastus2 --query "[?contains(name.value,'LowPriority')]" -o table
```

`Standard_NC6s_v3` is 6 vCPUs/node × maxNodes 2 = **12 low-priority NCSv3
vCPUs** needed. If the low-priority NCSv3 quota is 0 (common on a fresh
Visual Studio Enterprise subscription), the cluster CREATE will fail at deploy
with a quota error. Request the increase in the portal Quotas blade (ML →
region eastus2 → "Standard NCSv3 Family vCPUs (Low-priority)") BEFORE merging,
or the deploy.yml run will fail. The cluster resource itself is free at
`minNodes: 0`, but Azure still validates the quota ceiling at create.

## Acceptance

- `bicep build infra/main.bicep` exits 0; `bicep build-params` for dev/test/prod
  all succeed (test/prod omit `machineLearning`, so they must stay unaffected).
- Compiled `main.json` shows the cpu cluster name UNCHANGED and a new
  `cc-aio-dev-eus2-gpu` AmlCompute with `vmPriority: 'LowPriority'`,
  `scaleSettings.minNodeCount: 0`.
- On deploy, `cc-aio-dev-eus2-gpu` reaches `Succeeded` (subject to the quota
  check above).

## Out of scope

- The compute **instance** stays deferred (feature 009's open item is
  unchanged).
- No GPU on test/prod.
- The mechinterp pipeline that submits jobs to this cluster lives in the
  `mechinterp` repo (`mlplatform/`), not here.

## Follow-up (separate feature): keyless-datastore identity for jobs

When the `mlplatform` pipeline first submitted a job to this cluster, two RBAC
facts had to be set manually (live) that a future feature should encode here so
a clean `deploy.yml` reproduces the working state:

1. The GPU **compute's system-assigned managed identity** must exist and hold
   **Storage Blob Data Contributor** on the shared storage account — a job that
   reads the keyless (identity-based) datastore authenticates as the compute
   identity, and fails with "Identity of the specified managed compute is not
   found" without it. The `compute.bicep` module attaches `disableLocalAuth` but
   does not currently set `identity: { type: 'SystemAssigned' }` on the cluster
   or grant it the blob role; add both (guarded by `enableMl`).
2. A human **operator's user** needs Storage Blob Data Contributor on the same
   account to upload job code (keyless upload runs as the caller). This is an
   operator grant, not infra, but worth a note in the ML quickstart.

These are additive and do not change the cluster shape this feature ships.
