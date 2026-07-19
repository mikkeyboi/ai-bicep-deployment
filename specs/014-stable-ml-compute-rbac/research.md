# Research: ARM deployment identity and role assignments

## Observed failure

Deployment run `29702062371` passed validation and what-if, created the A100 and
H100 AmlCompute resources, then failed in nested deployment
`ra-ml-compute-blob-0` with `RoleAssignmentUpdateNotPermitted`.

The old index zero represented the V100 principal. After V100/T4 were removed,
index zero represented A100. Reusing the nested deployment name asked ARM to
reconcile immutable principal/scope identity through an existing deployment
slot.

## Decision

Use the resolved cluster resource name in the nested deployment name. Cluster
names are stable, centrally generated, unique within the workspace, and already
fit ARM deployment-name limits.

## Alternatives rejected

- **Keep array indices:** reorder/removal remains unsafe.
- **Include only the principal ID:** runtime-only identity makes what-if less
  readable and deployment names less operationally traceable.
- **Delete prior deployment history manually:** treats the symptom and makes every
  future cluster-array edit fragile.
