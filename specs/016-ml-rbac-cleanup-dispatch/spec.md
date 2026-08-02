# Feature 016: Guarded ML RBAC cleanup dispatch

**Branch**: `016-ml-rbac-cleanup-dispatch` | **Constitution**: v1.2.0

## Problem

The additive scope-identity migration correctly created CPU's storage grant, but
A100/H100 already held equivalent storage grants from earlier partial deployments.
Azure rejected the new deterministic IDs with `RoleAssignmentExists`. The local
certificate principal can inspect these grants but cannot delete them; the
protected deployment OIDC identity has the required RBAC authority.

## Decision

Add a default-off workflow-dispatch migration that discovers the uniquely tagged
dev workspace and storage account, asserts one A100 and one H100 target, asserts
exactly one matching storage-scoped Blob Contributor grant for each, deletes only
those two superseded grants, and then runs the normal deployment.

## Requirements

- FR-001: Push deployments never run cleanup.
- FR-002: Cleanup requires an explicit boolean dispatch input and confirmation token.
- FR-003: Resource discovery uses standard tags and fails closed on ambiguity.
- FR-004: Only A100/H100 storage-scoped Blob Contributor grants are eligible.
- FR-005: Any unexpected count aborts before deletion.
- FR-006: Cleanup is restricted to dev in both workflow and script.
- FR-007: Both targets and both deterministic assignment identities validate as
  legacy or final before any deletion.
- FR-008: A final scope-salted ID is retained and skipped; any unknown ID aborts
  cleanup, allowing mixed final/legacy state to resume safely.
- FR-009: Azure CLI failures never print command arguments or resource IDs.
- FR-010: The assignment resource-ID suffix, reported name, and calculated legacy
  GUID must match exactly; principals and assignment IDs must be distinct.
- FR-011: After a valid migration begins, declarative convergence runs even if a
  deletion fails, while the workflow still reports failure.

## Acceptance

- Standard-library unit tests cover cardinality, atomic preflight, final-ID reruns,
  pagination, environment/confirmation guards, and sanitized failures.
- CI validation passes.
- One explicit dev dispatch deletes two superseded grants and deployment succeeds.
- Subsequent default deployments are non-destructive and idempotent.
