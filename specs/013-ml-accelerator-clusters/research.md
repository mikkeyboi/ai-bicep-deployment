# Research: accelerator strata and low-priority capacity

## Live discovery (2026-07-19)

The Azure ML size catalog in eastus2 reports:

| SKU | GPU count | Low-priority capable | Approx. Linux low-priority retail price |
|---|---:|---|---:|
| `Standard_NC24ads_A100_v4` | 1 | yes | USD 0.74/hour |
| `Standard_NC40ads_H100_v5` | 1 | yes | USD 1.40/hour |

Prices are discovery-time estimates, not a cost guarantee. Actual billing and capacity can change.

The generic VM SKU API reports `NotAvailableForSubscription` restrictions for
both SKUs and the generic Compute usage endpoint reports a 20-vCPU regional
low-priority pool. Neither is the governing AzureML AmlCompute cluster quota.
`MLClient.compute.list_usage(location="eastus2")` reports `Total Cluster Low
Priority Regional vCPUs` with current usage 0 and limit 200. At max two nodes
each, A100 consumes 48 and H100 consumes 80, so both definitions fit under the
128-vCPU combined ceiling. Allocation remains subject to transient capacity.

## Experimental role

- The completed T4 cloud smoke is retained as execution-boundary evidence, not
  as an active comparison stratum.
- A100 and H100 are the only desired benchmark accelerator pools.
- One GPU per VM permits inter-node communication measurements but does not establish intra-node NVLink behavior.
- Low-priority pre-emption is part of the checkpoint/recovery experiment, but involuntary eviction timing is not deterministic.

## Alternatives rejected

- **One mutable `gpu` cluster:** changing its SKU destroys hardware identity in run metadata and risks replacement.
- **Dedicated priority:** unnecessary cost for restartable experiments and currently unavailable family quota.
- **Imperative cluster creation only:** leaves the reproducible IaC story incomplete.
- **Using generic Compute quota for AmlCompute:** reports the wrong pool; use
  AzureML `compute.list_usage` for `Total Cluster Low Priority Regional vCPUs`.
- **Treating quota as allocation proof:** ignores transient low-priority capacity.

## Cost posture

Every accelerator cluster has zero minimum nodes. Idle definitions do not incur VM charges. Jobs should set fixed token budgets and record wall time, observed allocation, and discovery-time price separately.
