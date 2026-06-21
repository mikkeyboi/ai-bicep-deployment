# Feature 012: ML compute identity for keyless-datastore reads

**Branch**: `012-ml-compute-identity` | **Constitution**: v1.2.0
**Follows**: 010 (GPU cluster), 011 (ACR pin).

## Problem

An AmlCompute job that reads a keyless (identity-based) datastore - the
mechinterp `trials_datalake` - authenticates as the **cluster's own MSI**, not
the workspace MSI. The IaC clusters had no identity, so the first pipeline run
failed:

```
Identity of the specified managed compute ... is not found
```

(Set manually live to unblock; this encodes it so a clean deploy reproduces it.)

## Change

- `compute.bicep`: clusters get `identity: { type: 'SystemAssigned' }` and output
  `computeClusterPrincipalIds`.
- `workload.bicep`: one `Storage Blob Data Contributor` grant per cluster MSI on
  the shared storage account, created after `ml-compute` (`dependsOn` so the
  principalIds exist). Distinct principal+name from `raMlBlob`, so no
  `RoleAssignmentExists` collision (Azure dedupes by scope+principal+role).

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| II - no secrets/IDs in source | PASS | PrincipalIds flow from module outputs at deploy time; none in source. |
| V - names from naming.bicep | N/A | RBAC names are `guid()`-derived in the role module. |
| VIII - consumption-only | PASS | No billable resource; an RBAC grant. |

No Complexity Tracking entries.

## Acceptance

- `bicep build` + `build-params` dev/test/prod exit 0. **Verified.**
- Compiled ARM sets `SystemAssigned` on clusters and emits `ra-ml-compute-blob-*`.
- On deploy the grant succeeds (no collision; the prior manual grant was removed).

## Out of scope

- The operator-user storage grant (to upload job code) stays a manual per-developer
  step, not infra.
