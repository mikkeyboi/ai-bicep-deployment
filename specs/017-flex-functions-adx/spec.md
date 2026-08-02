# Feature 017 — Flex Consumption Function App + Data Explorer telemetry

## Problem

Two resources backing the agent-workflow sample exist in the dev subscription and are
**not in this repository at all**:

| Resource | How it got there | Consequence |
|---|---|---|
| `Microsoft.Web/sites` (Linux Consumption, Y1) | `az functionapp create` by hand | Not reproducible; RBAC grants applied manually |
| `Microsoft.Kusto/clusters` + `hvac` database | Portal | Not reproducible; no tags, no review, no rollback |

A clean deployment of this repo does not produce the environment the workload actually
runs in. That is the failure this feature closes.

There is also a deadline. The portal reports:

> Migrate your app to Flex Consumption as Linux Consumption will reach EOL on
> September 30 2028 and will no longer be supported.

## Why this is a recreate, not a SKU change

Linux Consumption (`Y1`/`Dynamic`) **cannot be converted to Flex Consumption in place.**
The hosting plan tier is immutable for an existing app, so migration means a new
`serverfarm`, a new `site`, and a **new system-assigned principal** — which invalidates
every role assignment the old identity held.

This matters for how the change is reviewed: it is not a parameter tweak with a small
blast radius. It creates parallel resources and abandons the old ones, and the old app
must be deleted explicitly afterwards.

## Scope

**In:**

- `modules/function-app/main.bicep` — Flex Consumption app + plan, system-assigned
  identity, keyless (`SystemAssignedIdentity`) deployment-container mount.
- `modules/data-explorer/main.bicep` — ADX cluster + database.
- Naming functions `functionApp`, `functionPlan`, `adxCluster`.
- Optional, default-off config blocks `functionApp` and `dataExplorer`.
- **Back-filled RBAC** for the function's identity: Storage Blob Data Contributor
  (deployment package + cursor), Cognitive Services User (Foundry data plane), Search
  Index Data Reader (knowledge base). These were manual `az role assignment create`
  calls and are the open item PR #72 in the consuming repo recorded.

**Out:**

- **KQL schema (tables, functions, dashboard queries).** Data-plane DDL that ARM cannot
  express. It stays in the consuming repo's `kql/schema.kql`, applied by an idempotent
  script.
- **The ADX database *ingestor* grant.** Kusto database principals are a data-plane
  concept with no ARM role-assignment equivalent (`.add database ... ingestors`).
  Applied by the same script. `functionAppPrincipalId` is emitted so no human copies a
  GUID between portals.
- **Function application code.** Deployed by the consuming repo's own workflow; this
  repo owns the hosting, not the payload.

## Runtime version

Python **3.12**, not 3.11. Support windows:

| Version | Supported until |
|---|---|
| 3.11 | 2027-10-31 |
| 3.12 | 2028-10-31 |

Creating a new app on 3.11 would put its runtime EOL *before* the Linux Consumption
deadline this feature exists to get ahead of.

## Constraints honoured

- No secrets, keys, or identifiers in source. No `listKeys()` added — the deployment
  container is mounted with the app's own identity.
- No hardcoded region/SKU literals in modules; everything flows from the parameter file
  through typed config (Principle IV).
- Both features default **off**. `test`/`prod` omit the blocks and compile unchanged.

## Acceptance

1. `bicep build infra/main.bicep` exits 0.
2. `bicep build-params` succeeds for **dev, test, and prod** — proving the new optional
   fields are backward compatible.
3. Compiled ARM contains `FC1`/`FlexConsumption` and `Microsoft.Kusto/clusters`.
4. No new `listKeys` in compiled output.
5. Deployed dev app reaches the Foundry endpoint and writes rows to ADX **using only its
   managed identity**.
6. The superseded Y1 app and its plan are deleted after the Flex app is verified.
