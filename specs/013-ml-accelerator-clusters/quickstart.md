# Quickstart: validate accelerator clusters

## Compile

```bash
export PATH="$HOME/.local/bin:$PATH"
mkdir -p /tmp/bicep-013
bicep build infra/main.bicep --outdir /tmp/bicep-013
bicep lint infra/main.bicep
for environment in dev test prod; do
  bicep build-params "infra/parameters/main.${environment}.bicepparam" \
    --outfile "/tmp/bicep-013/${environment}.json"
done
```

Inspect compiled output for distinct `gpu`, `gpu-t4`, `gpu-a100`, and `gpu-h100` names, low-priority priority, zero minimum nodes, and the intended SKUs.

## Live gates

Before deployment:

1. confirm Azure ML still lists each requested SKU as low-priority capable;
2. inspect regional low-priority vCPU usage and quota;
3. run subscription validation and what-if;
4. review any proposed replacement or deletion before create.

After deployment, distinguish two checks:

- **definition smoke:** cluster provisioning state is `Succeeded` at zero nodes;
- **allocation smoke:** a one-node job reaches `Running` and records its actual VM SKU.

A quota/capacity allocation failure is a structured result, not permission to switch silently to another SKU. Do not submit two-node jobs until one-node allocation succeeds.
