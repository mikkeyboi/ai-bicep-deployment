# Research: 007 Azure ML Workspace + Compute

## D1 — Resource model: standard workspace vs Foundry hub

Azure ML and AI Foundry now overlap at the resource level, which the
constitution (IV) addresses: **Foundry** uses
`Microsoft.CognitiveServices/accounts` kind=`AIServices`, and *hub-based*
ML workspaces (`Microsoft.MachineLearningServices/workspaces`
kind=`Hub`/`Project`) are deprecated **as the Foundry mechanism**.

This feature deploys a **standard training workspace**
(`kind=Default`, i.e. `kind` omitted). That is *not* a Foundry hub — it
is the classic Azure ML workspace used for notebooks, training jobs, and
managed compute. Principle **VIII** explicitly lists
`Microsoft.MachineLearningServices/workspaces` as an allowed first-party
consumption resource, so a standard workspace is in-bounds. We do **not**
set `kind: 'Hub'` and we do not create `connections` or
`workspaceHubConfig`.

## D2 — API version

- GA `2024-10-01` exists for both `workspaces` and `workspaces/computes`.
- **However**, `systemDatastoresAuthMode` (the keyless-datastore switch)
  is **not in the GA schema** — `bicep build` flags BCP037 on GA and ARM
  would drop the property, silently falling back to access-key datastores.
- The property *is* present in the **preview** line. The official Azure
  quickstart `aifoundry-network-restricted/modules/ai-hub.bicep` uses
  `workspaces@2024-10-01-preview` with exactly this property.
- **Decision**: use `2024-10-01-preview` for the workspace and computes.
  This matches the repo's existing reliance on preview CognitiveServices
  APIs (`2025-04-01-preview`).

## D3 — Naming + GPU-readiness

- CAF abbreviations: workspace `mlw`; compute instance `ci`; compute
  cluster `cc`.
- **Compute name regex**: `^[a-zA-Z](?![a-zA-Z0-9-]*-\d+$)[a-zA-Z0-9\-]{2,23}$`
  — must start with a letter, ≤24 chars, and **must not end in
  `-<digits>`**. A trailing processor token (`-cpu`/`-gpu`) satisfies all
  three; a numeric instance suffix (`-001`) would have violated the
  no-trailing-digits rule.
- We map the **processor class** to the existing CAF "instance" slot of
  the naming functions, so names are `ci-aio-dev-eus2-cpu`,
  `cc-aio-dev-eus2-cpu`. Appending a `processor:'gpu'` entry later yields
  `…-gpu` **without renaming** the CPU targets. Renames would force
  resource replacement, so this is the property we want.
- **Workspace name regex**: `^[a-zA-Z0-9][a-zA-Z0-9_-]{2,32}$` —
  `mlw-aio-dev-eus2` (16 chars) fits comfortably.

## D4 — Keyless datastores + required RBAC

`systemDatastoresAuthMode='identity'` creates `workspaceblobstore` /
`workspacefilestore` **without** stored account keys. The workspace's
identity then authenticates to storage over Entra. Per Microsoft's
"disable shared key access to the workspace storage account" + "set up
service authentication" docs, the identity needs:

| Target | Role | Why |
|---|---|---|
| Shared storage | **Storage Blob Data Contributor** | `workspaceblobstore` R/W |
| Shared storage | **Storage File Data Privileged Contributor** (built-in role; GUID lives only in the allowlisted `role-assignment` module) | `workspacefilestore` R/W |
| Shared Key Vault | **Key Vault Secrets Officer** | workspace writes connection/datastore secrets |

The workspace MSI is a **different principal** from the workload MI, so
reusing "Storage Blob Data Contributor" does not trigger
`RoleAssignmentExists` (Azure dedupes by scope+principal+role, not by
name — lesson from feature 005).

We use the workspace **system-assigned** identity (simplest; no
chicken-and-egg of granting a UAMI before the workspace exists). The
role assignments `dependsOn` the workspace implicitly via
`ml.outputs.principalId`.

## D5 — Cost posture

- Compute **cluster** `minNodeCount: 0` → scales to zero when idle, so a
  CPU cluster left running costs nothing until a job is submitted.
- Compute **instance** is a single always-on VM while running; we set an
  optional `idleTimeBeforeShutdown` (`PT30M` in dev) so a forgotten box
  auto-stops.
- Dev uses small CPU SKUs (`Standard_DS3_v2`). GPU SKUs (NC/ND-series)
  need separate quota approval and are intentionally not deployed yet.

## D6 — What we did NOT do

- No dedicated ML storage/KV/ACR (reused shared deps; ACR is optional and
  only needed for custom Docker environments — deferred).
- No private endpoints / managed VNet isolation (dev = public, parity
  with the existing stack; a networking feature can add this pre-prod).
- No `kind: 'Hub'`, no `connections`, no model deployments on the
  workspace (those belong to Foundry per Constitution IV).
