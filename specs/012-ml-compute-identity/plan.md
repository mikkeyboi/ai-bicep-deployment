# Implementation plan: ML compute identity

## Summary

Attach a system-assigned identity to every configured AmlCompute cluster and grant each identity Storage Blob Data Contributor on the shared storage account. This makes keyless datastore reads and writes reproducible from a clean deployment.

## Technical approach

1. Extend the existing compute module to declare `SystemAssigned` identity on clusters and return principal IDs in configuration order.
2. Map configured clusters to those principal IDs in `workload.bicep`.
3. Reuse the existing role-assignment module for one storage grant per cluster.
4. Preserve the current workspace, compute names, scale settings, and environment parameter shape.

## Constitution Check

| Principle | Status | Evidence |
|---|---|---|
| I. Declarative and idempotent | PASS | Identity and RBAC are expressed in Bicep with deterministic role-assignment names. |
| II. No identifiers or secrets | PASS | Principal IDs are runtime outputs; no IDs or credentials enter source. |
| III. OIDC-first | PASS | Deployment authentication is unchanged. |
| IV. Modular templates | PASS | Compute identity stays in the compute module; RBAC uses the shared role module. |
| V. Naming and tagging | PASS | Existing compute names and tags are unchanged. |
| VI. Validation gates | PASS | Build, all parameter files, validate, what-if, and secret scanning remain required. |
| VII. Environment parity | PASS | The generic module applies to any configured environment. |
| VIII. Consumption only | PASS | Managed identity and RBAC add no Marketplace dependency or idle cost. |

## Complexity Tracking

No deviations.
