# Data model: stable ML compute RBAC deployment

| Value | Source | Stability |
|---|---|---|
| cluster name | centrally resolved `mlClusters[*].name` | stable across array order |
| cluster principal ID | `mlCompute.outputs.computeClusterPrincipalIds[*]` | bound to cluster identity |
| nested deployment name | `ra-<cluster-name>-blob` | unique per cluster |
| role assignment name | scope + principal + role GUID function | idempotent per grant |
| scope | shared storage account | stable |

The list index remains only the correspondence mechanism between a resolved
cluster record and the compute module's ordered principal-ID output. It is not a
resource identity.
