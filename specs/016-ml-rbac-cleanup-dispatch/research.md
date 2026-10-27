# Research: partial deployment and duplicate role semantics

Deployment run `29704305990` showed CPU's scope-salted grant no longer failed,
while A100/H100 returned `RoleAssignmentExists`. Earlier failed deployments had
already committed one correct storage-scoped grant for each accelerator under the
old IDs. Azure prevents a second grant with the same scope, principal, and role
even when the resource GUID differs.

The safe migration is therefore:

1. authenticate with the existing OIDC identity that owns RBAC deployment;
2. discover exact target principals and storage scope;
3. delete exactly one superseded A100/H100 grant each;
4. run the normal template, which recreates both under the final deterministic IDs.

Local credential elevation was rejected because it would widen standing
privileges solely for a one-time migration.
