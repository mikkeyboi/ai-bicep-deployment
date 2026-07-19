# Feature 014: Stable ML compute RBAC deployments

**Branch**: `014-stable-ml-compute-rbac` | **Constitution**: v1.2.0

## Problem

The feature-013 deployment created both requested accelerator clusters but failed
while updating keyless-storage RBAC. The nested role-assignment deployments were
named by array index. Removing V100/T4 shifted A100/H100 into indices previously
used by different cluster principals, and ARM rejected the attempted immutable
role-assignment update.

## Decision

Name each per-cluster RBAC deployment from the resolved AmlCompute cluster name,
not its array position. Keep the role assignment itself deterministic from scope,
principal, and role.

## Requirements

- FR-001: Reordering, adding, or removing cluster entries must not reuse another
  cluster's nested RBAC deployment identity.
- FR-002: Each cluster receives Storage Blob Data Contributor at storage-account
  scope through its own system-assigned identity.
- FR-003: CPU/A100/H100 compute definitions and scale settings remain unchanged.
- FR-004: Dev/test/prod parameter compilation remains valid.

## Acceptance

- Bicep build/lint and all parameter builds pass.
- Compiled output derives the nested deployment name from `cc.name`.
- Subscription validate and what-if pass.
- Redeployment succeeds and A100/H100 role assignments exist at storage scope.
- Legacy V100/T4 deletion occurs only after the successful redeployment.

## Out of scope

- Changing accelerator SKUs or quotas.
- Changing role privileges.
- Training jobs.
