# Feature 015: Storage-role scope migration

**Branch**: `015-storage-role-scope-migration` | **Constitution**: v1.2.0

## Problem

The stable per-cluster deployment names reached the CPU grant and exposed a
second migration defect. Earlier deployments created compute role assignments at
resource-group scope while deriving their GUID from the intended storage account.
The corrected storage-scoped resource reused that GUID, and Azure rejected moving
an immutable role assignment between scopes with `RoleAssignmentUpdateNotPermitted`.

## Decision

Include the explicit scope kind in storage-account role-assignment GUID
derivation. Preserve existing resource-group GUID derivation for backward
compatibility. This creates the correct narrow grant additively before obsolete
broad grants are removed.

## Requirements

- FR-001: Storage-scoped and resource-group-scoped grants cannot share a GUID.
- FR-002: Existing resource-group callers retain their current identity.
- FR-003: Storage grants remain deterministic across redeployments.
- FR-004: A100/H100/CPU grants converge before broad-grant cleanup.

## Acceptance

- Bicep build/lint and all parameter builds pass.
- Compiled storage GUID includes a stable scope-kind discriminator.
- CI validate/what-if pass.
- Dev deployment succeeds.
- Correct storage-scoped grants exist before broad grants are deleted.
