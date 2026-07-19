# Implementation plan: guarded ML RBAC cleanup dispatch

## Approach

1. Add a standard-library Python script that shells only to authenticated `az`.
2. Discover workspace/storage by standard dev/workload tags.
3. Discover A100/H100 compute principals through ARM.
4. Assert and delete exactly one matching storage grant per target.
5. Guard the step behind a default-false workflow-dispatch boolean.
6. Run the normal deployment immediately after cleanup.

## Constitution Check

| Principle | Status | Evidence |
|---|---|---|
| I. Declarative and idempotent | PASS | Cleanup is a bounded one-time migration before declarative convergence. |
| II. No identifiers or secrets | PASS | IDs are discovered at runtime and never printed. |
| III. OIDC-first | PASS | Cleanup uses the existing protected deployment identity. |
| IV. Modular, parameterized | PASS | Environment and targets are discovered from standard metadata. |
| V. Naming and tagging | PASS | Discovery depends on constitution-standard tags. |
| VI. Validation gates | PASS | CI and fail-closed runtime assertions apply. |
| VII. Environment parity | PASS | Migration is explicitly dev-only and default-off. |
| VIII. Consumption only | PASS | No billing change. |

## Complexity Tracking

| Deviation | Reason | Mitigation |
|---|---|---|
| Imperative one-time deletion | Azure role-assignment scope/identity is immutable and Bicep cannot delete the superseded IDs during additive migration. | Default-off dispatch, exact target/count assertions, no IDs in output, followed immediately by declarative deployment. |

## Rollback

Do not rerun cleanup after convergence. The default false input preserves the
normal non-destructive deployment path.
