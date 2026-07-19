# Feature 013: Low-priority accelerator clusters

**Branch**: `013-ml-accelerator-clusters` | **Constitution**: v1.2.0  
**Depends on**: 012 (compute identities for keyless datastores)

## Problem

The Azure ML workspace has legacy V100 and T4 clusters, but the controlled
DDP/FSDP/ZeRO comparison now targets larger-memory A100 and H100 accelerators.
Keeping obsolete GPU pools in desired state adds noise and maintenance without
serving the registered comparison.

The current compute schema derives a cluster name only from `processor`, so it cannot declare more than one GPU cluster without a name collision.

## Decision

Extend cluster configuration with an optional naming suffix and declare only two
scale-to-zero low-priority GPU strata in dev:

- A100: `Standard_NC24ads_A100_v4`, max two nodes;
- H100: `Standard_NC40ads_H100_v5`, max two nodes.

Both use `minNodes: 0`, `LowPriority`, and restartable jobs. The legacy V100 and
T4 clusters are removed from desired state and explicitly deleted only after the
new cluster resources provision successfully.

## Availability and quota boundary

Azure ML's workspace size catalog reports both requested SKUs as low-priority
capable in eastus2. AzureML's governing `Total Cluster Low Priority Regional
vCPUs` quota is 200, with zero currently used. Two A100 nodes require 48 vCPUs
and two H100 nodes require 80, for a combined ceiling of 128. The generic Compute
API reports a different 20-vCPU pool; that is not the AmlCompute cluster quota.

Quota is sufficient for the declared maxima. Successful node allocation still
depends on transient low-priority capacity, so acceptance distinguishes resource
provisioning from a one-node allocation smoke.

## Functional requirements

- FR-001: Existing CPU compute must remain unchanged.
- FR-002: Cluster config may optionally provide a CAF instance suffix.
- FR-003: A100 and H100 names must be distinct and centrally generated.
- FR-004: All GPU clusters use low-priority VMs and scale to zero.
- FR-005: Every new cluster receives the feature-012 managed identity and keyless-storage role binding.
- FR-006: Test and prod parameter files remain valid without ML configuration.
- FR-007: Documentation must state quota, pre-emption, capacity, topology, and claim limits.
- FR-008: V100 and T4 are absent from desired dev state and are deleted only
  after A100/H100 definitions reach `Succeeded`.

## Acceptance

- Bicep build/lint and dev/test/prod parameter compilation pass.
- Compiled dev output contains only `gpu-a100` and `gpu-h100` GPU AmlCompute
  names with the registered SKUs and low-priority scale settings.
- Existing CPU compute is unchanged.
- Subscription validate and what-if complete before deployment.
- Both new cluster resources reach `Succeeded`.
- Legacy V100 and T4 resources are then explicitly removed.
- A separate one-node allocation smoke records either success or a structured quota/capacity failure; cluster creation alone is not evidence that GPU capacity was allocated.

## Out of scope

- Dedicated GPU quota.
- Guaranteed low-priority allocation.
- Model training code or benchmark conclusions.
- Claims about multi-GPU NVLink or large-cluster scaling from one-GPU VMs.
