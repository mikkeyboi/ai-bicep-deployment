# Tasks: guarded ML RBAC cleanup

- [x] Capture live `RoleAssignmentExists` for A100/H100.
- [x] Add fail-closed discovery/deletion script.
- [x] Add default-off workflow-dispatch guard.
- [x] Validate script syntax/help and workflow YAML.
- [x] Run privacy, gitleaks, and diff checks.
- [x] Address independent destructive-path safety review findings.
- [x] Add standard-library migration tests to CI.
- [ ] Open and review the public PR.
- [ ] Dispatch one-time migration and deployment.
- [ ] Verify final storage grants and default idempotence.
- [ ] Remove obsolete broad grants and V100/T4 clusters.
