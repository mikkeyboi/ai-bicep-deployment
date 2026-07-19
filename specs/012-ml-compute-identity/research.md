# Research: AmlCompute identity and keyless datastores

## Decision

Use a system-assigned managed identity on every AmlCompute cluster. Azure ML jobs accessing an identity-based datastore execute as the compute identity, not automatically as the workspace identity.

## Evidence from the existing workload

The first keyless pipeline submission failed because the configured compute had no managed identity. Adding an identity and a storage data-plane grant unblocked the job. This feature encodes that live correction in the reproducible substrate.

## Alternatives rejected

- **Account keys or SAS tokens:** conflicts with managed-identity policy and creates secret lifecycle work.
- **Workspace identity only:** insufficient for job-time datastore access from managed compute.
- **Operator identity inside the job:** couples execution to a person and cannot support unattended runs.
- **Broad subscription-scoped storage access:** unnecessary; the shared storage account is the narrow required scope.

## Ordering

The role assignment depends on cluster creation because the system-assigned principal ID does not exist before the compute resource is provisioned. Data-plane RBAC may still take time to propagate; a newly created cluster can require a short retry before its first job.
