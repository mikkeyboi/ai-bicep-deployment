# Feature 013: Low-priority accelerator clusters

**Branch**: `013-ml-accelerator-clusters` | **Constitution**: v1.2.0  
**Depends on**: 012 (compute identities for keyless datastores)

## Problem

The Azure ML workspace has reproducible CPU and V100 compute, while a T4 cluster was added live to unblock experiments and is not yet represented in Bicep. A controlled DDP/FSDP/ZeRO comparison also needs larger-memory accelerators to separate software strategy limits from a 16 GB device ceiling.

The current compute schema derives a cluster name only from `processor`, so it cannot declare more than one GPU cluster without a name collision.

## Decision

Extend cluster configuration with an optional naming suffix and declare four scale-to-zero low-priority GPU strata in dev:

- V100: `Standard_NC6s_v3`, existing baseline, max two nodes;
- T4: `Standard_NC8as_T4_v3`, backfill the live neutral-hardware target, max two nodes;
- A100: `Standard_NC24ads_A100_v4`, larger-memory replication stratum, max two nodes;
- H100: `Standard_NC40ads_H100_v5`, modern-accelerator replication stratum, max two nodes.

All remain `minNodes: 0`, `LowPriority`, and restartable. A100/H100 do not replace the registered T4 benchmark stratum; hardware generation is an explicit experimental axis.

## Availability and quota boundary

Azure ML's workspace size catalog reports both requested A100 and H100 SKUs as low-priority capable in eastus2. The generic VM SKU API reports subscription restrictions, and the current regional low-priority quota is 20 vCPUs. One A100 node needs 24 vCPUs and one H100 node needs 40 vCPUs.

Therefore this feature can reproducibly declare scale-to-zero clusters, but successful node allocation remains gated on quota and transient low-priority capacity. Acceptance distinguishes resource provisioning from a successful allocation smoke.

## Functional requirements

- FR-001: Existing CPU and generic V100 cluster names must remain unchanged.
- FR-002: Cluster config may optionally provide a CAF instance suffix.
- FR-003: T4, A100, and H100 names must be distinct and centrally generated.
- FR-004: All GPU clusters use low-priority VMs and scale to zero.
- FR-005: Every new cluster receives the feature-012 managed identity and keyless-storage role binding.
- FR-006: Test and prod parameter files remain valid without ML configuration.
- FR-007: Documentation must state quota, pre-emption, capacity, topology, and claim limits.

## Acceptance

- Bicep build/lint and dev/test/prod parameter compilation pass.
- Compiled dev output contains `gpu`, `gpu-t4`, `gpu-a100`, and `gpu-h100` AmlCompute names with the registered SKUs and low-priority scale settings.
- Existing CPU and V100 names are unchanged.
- Subscription validate and what-if complete without replacement of existing compute.
- Cluster resources reach `Succeeded` if Azure permits definitions above current allocation quota.
- A separate one-node allocation smoke records either success or a structured quota/capacity failure; cluster creation alone is not evidence that GPU capacity was allocated.

## Out of scope

- Dedicated GPU quota.
- Guaranteed low-priority allocation.
- Model training code or benchmark conclusions.
- Claims about multi-GPU NVLink or large-cluster scaling from one-GPU VMs.
