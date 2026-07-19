# Data model: accelerator clusters

## Cluster configuration

| Field | Type | Required | Meaning |
|---|---|---|---|
| `processor` | `cpu` or `gpu` | yes | broad compute class |
| `nameSuffix` | string | no | CAF instance segment used to distinguish multiple clusters of one processor class |
| `vmSize` | string | yes | Azure VM SKU, parameter-file only |
| `vmPriority` | Dedicated or LowPriority | no | Azure allocation priority |
| `scale` | object | yes | minimum, maximum, and idle scale-down duration |

If `nameSuffix` is omitted, naming remains backward compatible and uses `processor`.

## Dev instances

| Suffix | SKU | Priority | Min | Max |
|---|---|---|---:|---:|
| `cpu` | existing CPU SKU | Dedicated | 0 | 4 |
| `gpu` | existing V100 SKU | LowPriority | 0 | 2 |
| `gpu-t4` | T4 SKU | LowPriority | 0 | 2 |
| `gpu-a100` | A100 SKU | LowPriority | 0 | 2 |
| `gpu-h100` | H100 SKU | LowPriority | 0 | 2 |

Each cluster receives a system-assigned identity and one shared-storage data-plane role assignment through feature 012.
