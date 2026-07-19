# Implementation plan: storage-role scope migration

## Approach

1. Add `storageAccount` as the first input to the storage-scoped `guid()` call.
2. Leave resource-group identity unchanged.
3. Compile all environments and inspect the generated extension-resource ID.
4. Validate/what-if, deploy additively, and verify the narrow grants.
5. Delete obsolete broad grants only after verification.

## Constitution Check

| Principle | Status | Evidence |
|---|---|---|
| I. Declarative and idempotent | PASS | Scope-specific deterministic identity converges. |
| II. No identifiers or secrets | PASS | The discriminator is a public scope-kind label. |
| III. OIDC-first | PASS | Authentication is unchanged. |
| IV. Modular, parameterized | PASS | Scope behavior remains inside the shared role module. |
| V. Naming and tagging | PASS | No resource naming change outside role identity. |
| VI. Validation gates | PASS | Build, parameters, validate, what-if, and gitleaks apply. |
| VII. Environment parity | PASS | No environment schema change. |
| VIII. Consumption only | PASS | No billing or Marketplace change. |

## Complexity Tracking

No deviations.

## Rollback

Do not revert after broad grants are removed; doing so would recreate the GUID
collision with historical resource-group assignments.
