# Plan — 017 Flex Consumption Function App + Data Explorer

## Constitution Check

| Principle | Requirement | Status |
|---|---|---|
| I — Public repo hygiene | No subscription/tenant/object IDs, keys, emails | **Pass.** Endpoints and names resolve from module outputs; no GUIDs in source. Role names used, never role GUIDs. |
| II — No `listKeys()` outputs | Never emit storage/account keys | **Pass.** Flex mounts the deployment container with `authentication.type: SystemAssignedIdentity`. No key is read or emitted. |
| III — Spec-driven | `specs/NNN-<slug>/` per infra change | **Pass.** This feature. |
| IV — No literals in modules | Region/SKU/auth flow from bicepparam → main → workload → module | **Pass.** SKUs, runtime version, memory, and instance cap are typed config with defaults at the call site, not hardcoded in modules. |
| V — Standard tags | Every taggable resource tagged | **Pass.** Both modules take `tags` and apply it to cluster, database, plan, and site. |
| VIII — Consumption-only billing | No partner/marketplace SKUs | **Pass.** Flex Consumption is first-party serverless; ADX dev tier is a standard Azure SKU. No model deployments added. |
| Managed identity over keys | Prefer Entra to keys | **Pass, and strengthened.** ADX is Entra-only by design; the function's three role assignments replace manual grants. |

### Complexity Tracking

| Deviation | Justification | Alternative rejected |
|---|---|---|
| Two data-plane operations (KQL DDL, ADX ingestor grant) live outside IaC | ARM cannot express Kusto database principals or table DDL. Forcing them in would need a deployment script resource holding elevated credentials. | Embedding a `deploymentScripts` resource — adds a managed identity with cluster-admin rights to every deployment, to run something that is idempotent and already scripted in the consuming repo. Worse security for no reproducibility gain. |
| The migration abandons resources rather than mutating them | Flex is not reachable from Y1 in place; the plan tier is immutable. | An in-place SKU change — rejected because it is not possible, not because it is undesirable. |

## Sequence

1. Naming functions (`functionApp`, `functionPlan`, `adxCluster`).
2. Types: `functionAppConfig`, `dataExplorerConfig`, both optional on `environmentConfig`.
3. Modules: `function-app`, `data-explorer`.
4. Wire into `workload.bicep` behind `enableFunc` / `enableAdx`; add outputs.
5. Back-fill the three function-identity role assignments.
6. `main.dev.bicepparam` only. `test`/`prod` untouched.
7. Validate: build + build-params across all three envs.
8. Deploy dev, verify live, then delete the superseded Y1 app and plan.

## Risk

**What-if will report deletes.** The old Y1 app is not in the template, so it is
untouched by an incremental deployment — it must be removed deliberately in step 8, and
only after the Flex app is confirmed working. Do not let the deploy imply the old app is
gone.

**A new principal means a propagation window.** RBAC assignments on a freshly created
identity take a minute or two to become effective. A first invocation that fails with an
authorization error is expected and should be re-checked, not immediately "fixed".

## Type constraints

`skuTier` and `instanceMemoryMB` are declared as unions (`'Basic' | 'Standard'`,
`2048 | 4096`) rather than `string`/`int`. Both initially failed `bicep build` as loose
types, which is the argument for keeping them narrow: a bad value now fails at compile
time in CI instead of at deploy time in Azure.
