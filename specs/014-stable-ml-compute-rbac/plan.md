# Implementation plan: stable ML compute RBAC deployments

## Approach

1. Replace the array-index deployment name with a name derived from `cc.name`.
2. Preserve principal lookup by the corresponding output index.
3. Compile every environment and inspect generated deployment-name expressions.
4. Validate/what-if through CI, merge, and rerun the dev deployment.
5. Verify storage-scoped grants before deleting obsolete GPU clusters.

## Constitution Check

| Principle | Status | Evidence |
|---|---|---|
| I. Declarative and idempotent | PASS | Stable resource-derived deployment names converge across array changes. |
| II. No identifiers or secrets | PASS | Only existing symbolic cluster names are used. |
| III. OIDC-first | PASS | Authentication is unchanged. |
| IV. Modular, parameterized | PASS | The generic RBAC module and parameter flow remain unchanged. |
| V. Naming and tagging | PASS | Deployment identity derives from the centrally resolved compute name. |
| VI. Validation gates | PASS | Build, parameters, validate, what-if, and gitleaks remain required. |
| VII. Environment parity | PASS | No environment-specific schema change. |
| VIII. Consumption only | PASS | No billing or Marketplace change. |

## Complexity Tracking

No deviations.

## Rollback

Restore the index-based name only if every cluster array is immutable. That
condition is not acceptable for the current multi-accelerator design.
