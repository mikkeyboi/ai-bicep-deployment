# Module contract: ML compute identity

## `modules/machine-learning/compute.bicep`

### Existing inputs

- workspace name
- location
- tags
- resolved compute instances
- resolved compute clusters

### Required behavior

- every AmlCompute cluster declares a system-assigned identity;
- existing VM size, priority, Linux, networking, and scale settings remain unchanged;
- output `computeClusterPrincipalIds` preserves the order of the input cluster array.

### Outputs

- compute instance names
- compute cluster names
- compute cluster principal IDs

## `workload.bicep`

For each configured cluster, create one Storage Blob Data Contributor assignment
on shared storage using the corresponding principal ID. Role assignment creation
occurs after compute creation and uses the existing reusable role-assignment
module with `scopeKind: storageAccount`.

## `modules/role-assignment/main.bicep`

- `scopeKind` is optional and defaults to `resourceGroup`, preserving every
  existing caller.
- `scopeKind: storageAccount` creates the assignment as an extension resource on
  the storage account named by `scopeResourceId`.
- The deterministic assignment name continues to include scope resource ID,
  principal ID, and role definition ID.
