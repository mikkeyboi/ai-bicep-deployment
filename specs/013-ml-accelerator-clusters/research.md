# Research: accelerator strata and low-priority capacity

## Live discovery (2026-07-19)

The Azure ML size catalog in eastus2 reports:

| SKU | GPU count | Low-priority capable | Approx. Linux low-priority retail price |
|---|---:|---|---:|
| `Standard_NC24ads_A100_v4` | 1 | yes | USD 0.74/hour |
| `Standard_NC40ads_H100_v5` | 1 | yes | USD 1.40/hour |

Prices are discovery-time estimates, not a cost guarantee. Actual billing and capacity can change.

The generic VM SKU API reports `NotAvailableForSubscription` restrictions for both SKUs. Azure ML's catalog still exposes low-priority capability, which is a distinct pool. The regional low-priority quota is 20 vCPUs, while A100 requires 24 and H100 requires 40 per node. A job allocation is therefore expected to require a quota increase even if the scale-to-zero cluster resource can be created.

## Experimental role

- T4 remains the first controlled stratum because two one-GPU nodes already exist and bound the initial claims.
- A100/H100 are hardware replication strata, not replacements for the preregistered T4 comparison.
- One GPU per VM permits inter-node communication measurements but does not establish intra-node NVLink behavior.
- Low-priority pre-emption is part of the checkpoint/recovery experiment, but involuntary eviction timing is not deterministic.

## Alternatives rejected

- **One mutable `gpu` cluster:** changing its SKU destroys hardware identity in run metadata and risks replacement.
- **Dedicated priority:** unnecessary cost for restartable experiments and currently unavailable family quota.
- **Imperative cluster creation only:** leaves the reproducible IaC story incomplete.
- **Treating catalog visibility as allocation proof:** ignores regional quota and transient low-priority capacity.

## Cost posture

Every accelerator cluster has zero minimum nodes. Idle definitions do not incur VM charges. Jobs should set fixed token budgets and record wall time, observed allocation, and discovery-time price separately.
