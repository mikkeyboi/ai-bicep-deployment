# Quickstart: 007 Azure ML Workspace + Compute

## What this deploys (dev)

- `mlw-aio-dev-eus2` — standard Azure ML workspace (kind=Default), bound
  to the shared storage / Key Vault / App Insights, keyless datastores.
- `ci-aio-dev-eus2-cpu` — CPU compute instance (single-user dev box),
  30-min idle auto-shutdown.
- `cc-aio-dev-eus2-cpu` — CPU compute cluster, scales 0→4 nodes
  (idle → 0, so $0 when not running jobs).
- Three role assignments for the workspace MSI (blob, file, KV secrets).
- Diagnostic settings → shared Log Analytics.

## Validate locally (no az/bicep login needed)

```bash
export TMPDIR=~/.cache/bigtmp PATH="$HOME/.local/bin:$PATH"
bicep build infra/main.bicep --outdir /tmp/bb            # exit 0, no ML warnings
bicep lint  infra/main.bicep                             # error-level clean
for e in dev test prod; do
  bicep build-params infra/parameters/main.$e.bicepparam --outfile /tmp/p_$e.json
done                                                      # all exit 0 (optional field is back-compat)
```

## Confirm the VM size is available (operator, once logged in)

```bash
# After the workspace exists, list AML-supported sizes in the region:
az ml compute list-sizes --type AmlCompute \
  --workspace-name mlw-aio-dev-eus2 --resource-group rg-aio-dev-eus2 -o table
# Standard_DS3_v2 should appear. For GPU later, look for NC/ND-series and
# confirm you hold the matching quota (portal → Quotas → Machine Learning).
```

## Deploy (operator / CI)

```bash
# Local parity wrapper (validate → what-if → create):
scripts/deploy.sh -Environment dev -Location eastus2 \
  -Subscription <YOUR_SUBSCRIPTION_ID> -Tenant <YOUR_TENANT_ID>
```

Or merge to `main`, which triggers `deploy.yml` (OIDC) automatically.

## Smoke check after deploy

```bash
az ml workspace show -n mlw-aio-dev-eus2 -g rg-aio-dev-eus2 \
  --query "{name:name, datastoreAuth:systemDatastoresAuthMode, pna:publicNetworkAccess}"
az ml compute list -w mlw-aio-dev-eus2 -g rg-aio-dev-eus2 -o table
# Expect ci-aio-dev-eus2-cpu (Running/Stopped) and cc-aio-dev-eus2-cpu (0 nodes idle).
```

## Adding GPU later (the payoff)

1. Get NC/ND-series quota in eastus2 (portal → Quotas → Machine Learning).
2. In `main.dev.bicepparam`, append to `computeClusters` (and/or
   `computeInstances`):

   ```bicep
   { processor: 'gpu', vmSize: 'Standard_NC6s_v3', vmPriority: 'Dedicated'
     scale: { minNodes: 0, maxNodes: 2, nodeIdleTimeBeforeScaleDown: 'PT300S' } }
   ```

3. Redeploy. `cc-aio-dev-eus2-gpu` is **added**; the CPU targets keep
   their names (no replacement). That's the whole point of putting the
   processor class in the name.

## Rollback

Set `machineLearning.enabled: false` (or remove the block) and redeploy.
ARM is incremental; the workspace, computes, role assignments, and
diagnostic setting are removed. The shared storage/KV/App Insights are
untouched (they predate this feature).
