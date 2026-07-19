# Implementation plan: low-priority accelerator clusters

## Approach

1. Add optional `nameSuffix` to the shared AmlCompute cluster configuration.
2. Resolve cluster names through the existing central naming function using `nameSuffix` when present and `processor` otherwise.
3. Remove V100 and T4 from desired dev state.
4. Add only A100 and H100 entries in the dev parameter file.
5. Reuse the generic compute module, feature-012 system identities, and per-cluster storage RBAC.
6. Validate compiled names, priorities, scale settings, and unchanged test/prod output.
7. Run subscription validate/what-if, provision scale-to-zero definitions, and
   verify both resources before explicitly deleting legacy V100/T4 clusters.
8. Run one-node allocation smokes after definition provisioning.

## Constitution Check

| Principle | Status | Evidence |
|---|---|---|
| I. Declarative and idempotent | PASS | All clusters are Bicep resources; repeated deployment converges. |
| II. No identifiers or secrets | PASS | Only public SKU/priority/scale values are added to the dev parameter file. |
| III. OIDC-first | PASS | Deployment authentication is unchanged. |
| IV. Modular, parameterized | PASS | SKUs and scale settings stay in the environment parameter file; modules remain generic. |
| V. Naming and tagging | PASS | Optional suffixes flow through the central naming function. |
| VI. Validation gates | PASS | Build, all parameters, validate, what-if, and secret scan are required. |
| VII. Environment parity | PASS | The shared optional field is backward compatible; test/prod omit ML. |
| VIII. Consumption only | PASS | First-party AmlCompute, low-priority, scale-to-zero; no Marketplace dependency. |

## Complexity Tracking

No deviations.

## Rollback

Remove the two named accelerator entries and optional suffix wiring. Incremental
deployment does not delete previously created clusters automatically. Recreating
the legacy pools would require restoring their parameter entries and redeploying.
