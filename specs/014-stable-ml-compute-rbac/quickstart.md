# Quickstart: stable ML compute RBAC

```bash
export PATH="$HOME/.local/bin:$PATH" TMPDIR="$HOME/.cache/bigtmp"
out="$(mktemp -d /tmp/bicep014-XXXXXX)"
bicep build infra/main.bicep --outdir "$out"
bicep lint infra/main.bicep
for env in dev test prod; do
  bicep build-params "infra/parameters/main.$env.bicepparam" \
    --outfile "$out/$env.json"
done
```

After CI validate/what-if passes, deploy through the protected main workflow.
Verify A100/H100 compute provisioning and storage-scoped role assignments before
removing legacy clusters.
