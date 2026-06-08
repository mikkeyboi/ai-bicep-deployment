# Implementation Plan: 007 Azure ML Workspace + Compute

**Branch**: `007-azure-ml-compute` | **Date**: 2026-06-08
**Spec**: [spec.md](./spec.md) | **Constitution**: v1.2.0

## Summary

Add an optional Azure ML workspace (`kind=Default`) + one CPU compute
instance + one CPU compute cluster to dev, reusing shared deps with
keyless datastores. GPU-ready naming (processor in the name slot). All
behind an optional `machineLearning` config block so test/prod compile
and deploy unchanged.

## Directory Diff

```
infra/
  shared/
    naming.bicep            [MODIFIED] + mlWorkspace(), mlComputeInstance(), mlComputeCluster()
    types.bicep             [MODIFIED] + computeProcessor, amlComputeScale,
                                        amlComputeInstanceConfig, amlComputeClusterConfig,
                                        machineLearningConfig; environmentConfig += machineLearning?
  modules/
    machine-learning/main.bicep   [NEW] workspace + computes (keyless datastores)
    role-assignment/main.bicep    [MODIFIED] + 'Storage File Data Privileged Contributor' GUID
  workload.bicep            [MODIFIED] ML names, module, 3 RBAC grants, diagnostics, outputs
  main.bicep                [MODIFIED] workloadOutputs += ml* fields
  parameters/main.dev.bicepparam [MODIFIED] + machineLearning block (1 CPU instance, 1 CPU cluster)

specs/007-azure-ml-compute/ [NEW]
```

A new module is required: the ML workspace is a distinct resource family
(`Microsoft.MachineLearningServices`) with no existing module to reuse.

## Key Decisions

- **`kind=Default`, not a Foundry hub.** Constitution IV deprecates
  *hub-based ML workspaces* (`kind=Hub`/`Project`) **as the AI Foundry
  mechanism** — Foundry moved to `Microsoft.CognitiveServices` AIServices
  accounts. A plain **training** workspace (`kind=Default`) is a
  different capability and is **explicitly allowed** by Principle VIII,
  which names `Microsoft.MachineLearningServices/workspaces` as a
  permitted first-party consumption resource. We deploy a standard
  workspace and do **not** set `kind=Hub`. See Constitution Check below.
- **Reuse shared deps + keyless datastores.** No dedicated ML storage/KV;
  the workspace binds the shared Storage/KV/App Insights and uses
  `systemDatastoresAuthMode=identity`, matching the "managed identity
  over keys" posture. The workspace's own MSI gets the storage + KV roles
  it needs.
- **GPU-ready naming.** Processor class (`cpu`/`gpu`) occupies the CAF
  instance slot, so a GPU target is added by appending one config entry
  without renaming (and therefore without replacing) the CPU targets.

## Constitution Check (v1.2.0)

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Pure Bicep; deterministic names; what-if before create. |
| II. No Secrets / IDs / PII | PASS | No `listKeys()`; no GUIDs/emails; `friendlyName` is a generic label. Storage File Data Privileged Contributor **role-definition** GUID is a public built-in ID (same class already in the roleMap). |
| III. OIDC-First | PASS | No CI auth changes. |
| IV. Modular / Single Entry | PASS (with note) | New module under `modules/machine-learning/`; typed I/O; names from `shared/naming.bicep`; no region/SKU/VM literals in the module (all flow from the paramfile). **Note**: IV deprecates *Foundry hub* ML workspaces; this is a standard `kind=Default` training workspace, which IV does not forbid and VIII explicitly allows. |
| V. Naming & Tagging | PASS | `mlw-`/`ci-`/`cc-` CAF abbreviations; standard tag map on every resource. |
| VI. Validation Gates | PASS | lint + build + build-params(×3) locally; validate/what-if/gitleaks in CI. |
| VII. Environment Parity | PASS | `machineLearning` optional; test/prod omit it and are unaffected. |
| VIII. Consumption Billing | PASS | `Microsoft.MachineLearningServices/workspaces` + managed compute bill as Azure consumption; no Marketplace offer. |

## Complexity Tracking

| Deviation | Principle / Section | Why it is necessary | Mitigation |
|---|---|---|---|
| **Key Vault Secrets Officer** (write) granted to the ML workspace MSI, vs the workload MI's read-only **Key Vault Secrets User**. | Security & Compliance → least privilege. | The AML workspace control plane **writes** connection/datastore secrets into the bound Key Vault during workspace + datastore provisioning; a read-only role fails provisioning. | Scoped to the **shared vault only** and to the **workspace's own MSI** (a distinct principal from the workload MI). No keys are emitted as outputs. A later hardening pass can move ML to a dedicated vault to shrink the blast radius. |
| **Public network access** on the workspace + **node public IP** on the cluster in dev. | Security & Compliance → public access Disabled for prod; MI-over-network-isolation. | Dev parity with the rest of the stack (`enablePublicNetworkAccess: true`) and avoids the private-endpoint/managed-VNet complexity that is out of scope here. | Driven by `enablePublicNetworkAccess`, so prod (false) would render the workspace `Disabled`. ML is dev-only for now; a networking feature can add managed-VNet isolation before any prod promotion. |

## Phases

- **Phase 0**: Spec + plan + research + data-model + contracts + quickstart + tasks (this directory).
- **Phase 1**: Implement naming/types/role-map/module/workload/main/paramfile edits.
- **Phase 2**: Validate — `bicep lint` + `build` + `build-params`(dev/test/prod), compiled-ARM presence checks, privacy grep, gitleaks (CI), `az ml`/`what-if` (operator/CI).
- **Phase 3**: Deploy dev; smoke check (workspace show, compute list shows ci/cc, cluster idle at 0 nodes).
- **Phase 4**: Merge + sanitized DEPLOY_REPORT_007.md.

## Pre-deploy verification (az/bicep authoring env)

```bash
# Confirm the CPU VM size is available for AML in eastus2:
az ml compute list-sizes --type AmlCompute -o table   # (run against the workspace once it exists)
# Region capability for ML workspaces is not gated by region-capabilities.bicep
# (that map is model-deployment specific); ML workspaces are broadly available.
```
