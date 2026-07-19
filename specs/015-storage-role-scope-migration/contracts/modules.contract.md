# Module contract: scope-specific role identity

## `modules/role-assignment/main.bicep`

- Resource-group assignments preserve their existing deterministic GUID inputs.
- Storage-account assignments prepend the stable `storageAccount` discriminator
  to GUID inputs.
- Storage assignments remain extension resources on the storage account.
- Repeated deployment with the same scope, principal, and role is idempotent.
- A scope migration creates the new narrow assignment before external cleanup of
  the obsolete broad assignment.
