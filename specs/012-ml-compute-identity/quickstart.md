# Quickstart: validate ML compute identity

```bash
export PATH="$HOME/.local/bin:$PATH"
bicep build infra/main.bicep --outdir /tmp/bicep-012
bicep lint infra/main.bicep
for environment in dev test prod; do
  bicep build-params "infra/parameters/main.${environment}.bicepparam" \
    --outfile "/tmp/bicep-012/${environment}.json"
done
```

Before deployment, run the repository validation and what-if workflow. After deployment, confirm each AmlCompute cluster reports a system-assigned identity and can read and write an identity-based datastore without account keys.

A first job may need a retry while the storage data-plane role propagates. Do not replace the identity path with a key or SAS token.
