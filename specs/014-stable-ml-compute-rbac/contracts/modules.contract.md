# Module contract: stable per-cluster RBAC deployment

## `workload.bicep`

For every resolved ML cluster `cc`:

- nested module deployment name is derived from `cc.name`;
- principal ID comes from the matching ordered compute-module output;
- role remains Storage Blob Data Contributor;
- scope remains the shared storage account through `scopeKind: storageAccount`.

Adding, removing, or reordering another cluster must not change this cluster's
nested deployment name.

## `modules/role-assignment/main.bicep`

No contract change. Its deterministic role-assignment identity continues to use
scope resource ID, principal ID, and role definition ID.
