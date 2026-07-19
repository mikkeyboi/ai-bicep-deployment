# Data model: guarded cleanup target

| Field | Runtime source | Constraint |
|---|---|---|
| subscription | protected workflow secret | non-empty, never printed |
| workspace | ARM resources with dev/aio standard tags | exactly one |
| storage account | same resource group and standard tags | exactly one |
| compute | workspace ARM children | names end in `gpu-a100` / `gpu-h100` |
| principal | compute system identity | one per target |
| role assignment | storage-scope ARM list | exactly one Blob Contributor per target |

Any cardinality mismatch aborts before deletion.
