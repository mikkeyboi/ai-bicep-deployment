# Data model: ML compute identity

## Compute cluster

Existing cluster configuration is unchanged:

- processor
- VM size
- priority
- autoscale settings

The resolved Azure resource additionally has:

- identity type: `SystemAssigned`
- generated principal ID: deployment-time output only

## Storage role binding

For each configured cluster:

- principal: cluster system-assigned identity
- role: Storage Blob Data Contributor
- scope: shared storage account
- principal type: ServicePrincipal
- name: deterministic in the shared role-assignment module

No principal ID, role GUID, subscription ID, or storage credential is serialized into source or parameter files.
