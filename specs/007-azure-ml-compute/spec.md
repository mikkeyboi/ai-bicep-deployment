# Feature 007: Azure Machine Learning Workspace + Attached Compute

**Branch**: `007-azure-ml-compute` | **Status**: Draft | **Constitution**: v1.2.0

## Summary

Add an **optional Azure Machine Learning workspace**
(`Microsoft.MachineLearningServices/workspaces`, `kind=Default` — a
standard training workspace, *not* an AI Foundry hub) to the dev
environment, with one **compute instance** (single-user dev box) and one
**compute cluster** (autoscaling, scales to zero) attached. The workspace
reuses the existing shared Storage / Key Vault / App Insights and uses
**keyless datastores** (`systemDatastoresAuthMode=identity`).

The change is **GPU-ready by design**: the processor class (`cpu`/`gpu`)
is encoded in each compute resource name, so adding GPU capacity later is
a pure paramfile addition with **no rename** of the existing CPU targets.

## Motivation

The operator wants Azure ML for training/experimentation and intends to
add GPU compute later. Naming and structure must anticipate that so the
GPU addition is additive (no resource churn, no rename-driven
replacement of the CPU targets).

## User Scenarios

- **As the operator**, I deploy dev and get an ML workspace with a CPU
  compute instance (`ci-aio-dev-eus2-cpu`) and a CPU cluster
  (`cc-aio-dev-eus2-cpu`) so I can run notebooks and submit training
  jobs.
- **As the operator**, when GPU quota is approved I append one
  `processor: 'gpu'` entry with a GPU `vmSize` and redeploy; the new
  `cc-aio-dev-eus2-gpu` appears alongside the unchanged CPU targets.
- **As a reviewer**, I confirm test/prod (which omit `machineLearning`)
  compile and deploy unchanged.

## Functional Requirements

- **FR-1** A standard ML workspace (`kind=Default`) is deployed in
  `config.location` (eastus2 for dev) when `machineLearning.enabled` is
  true.
- **FR-2** The workspace reuses the shared Storage account, Key Vault,
  and Application Insights (no new dependency resources).
- **FR-3** Datastores are keyless: `systemDatastoresAuthMode=identity`.
  The workspace's system-assigned MSI is granted **Storage Blob Data
  Contributor** + **Storage File Data Privileged Contributor** on the
  shared storage and **Key Vault Secrets Officer** on the shared vault.
- **FR-4** Zero or more compute instances and clusters are attached from
  typed config arrays. Each carries a `processor` (`cpu`/`gpu`) that
  drives its name and VM-family choice.
- **FR-5** Compute **names** encode the processor in the CAF instance
  slot: `ci-<workload>-<env>-<region>-<processor>` and
  `cc-<workload>-<env>-<region>-<processor>`. Names satisfy the AML
  compute regex (start with a letter, ≤24 chars, must not end in
  `-<digits>`).
- **FR-6** The compute cluster scales to zero (`minNodes: 0`) so an idle
  CPU cluster costs nothing. The compute instance supports an optional
  ISO-8601 idle-shutdown timeout.
- **FR-7** Diagnostic settings route workspace logs+metrics to the shared
  Log Analytics workspace.
- **FR-8** `machineLearning` is optional; omission (test/prod) leaves
  those environments unchanged (environment parity).
- **FR-9** No keys/secrets in outputs (`listKeys()` forbidden); outputs
  are IDs, name, principalId, and compute-name arrays only.

## Out of Scope

- Networking isolation (private endpoints / managed VNet) — dev uses
  public network access, consistent with the existing stack.
- GPU compute is *enabled* by the design but not *deployed* in this
  feature (needs NC/ND-series quota approval first).
- Model training pipelines, environments, datastores beyond the system
  defaults, online/batch endpoints.
- Adding ML to test/prod.

## Acceptance

- `bicep build` + `bicep lint` (no error-level) pass.
- `bicep build-params` passes for dev, test, prod (proves the optional
  field is back-compat).
- Compiled `main.json` shows the workspace, both computes, three ML role
  assignments, and the diagnostic setting; no new `listKeys()`.
- CI `validate` + `what-if` succeed; gitleaks clean.
