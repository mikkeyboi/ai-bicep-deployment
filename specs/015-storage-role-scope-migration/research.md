# Research: immutable Azure role-assignment scope

## Observed failure

Deployment run `29703960407` reached stable nested deployment
`ra-cc-aio-dev-eus2-cpu-blob` and failed with
`RoleAssignmentUpdateNotPermitted`. The principal was stable; the attempted
change was from the historical resource-group scope to storage-account scope.

## Mechanism

A role-assignment GUID is immutable with respect to tenant, application,
principal, and scope. The legacy module used the intended `scopeResourceId` in
GUID derivation even though the actual resource was scoped to `resourceGroup()`.
Reusing that GUID for the corrected storage extension resource attempts a scope
move rather than a new grant.

## Decision

Salt only storage-account assignment GUIDs with the scope-kind label. This is
additive, deterministic, and backward compatible for all resource-group callers.
After narrow grants are proven, remove historical broad grants explicitly.
