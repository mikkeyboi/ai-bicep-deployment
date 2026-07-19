# Tasks: storage-role scope migration

- [x] Capture the second live `RoleAssignmentUpdateNotPermitted` failure.
- [x] Add a scope-kind discriminator to storage assignment identity.
- [x] Compile and inspect all environments.
- [x] Run privacy, gitleaks, and diff checks.
- [ ] Open and review the public PR.
- [ ] Redeploy successfully.
- [ ] Verify storage-scoped CPU/A100/H100 grants.
- [ ] Remove obsolete resource-group grants.
- [ ] Delete legacy V100/T4 clusters.
