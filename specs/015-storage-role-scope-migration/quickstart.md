# Quickstart: storage-role scope migration

```bash
export PATH="$HOME/.local/bin:$PATH" TMPDIR="$HOME/.cache/bigtmp"
out="$(mktemp -d /tmp/bicep015-XXXXXX)"
bicep build infra/main.bicep --outdir "$out"
bicep lint infra/main.bicep
for env in dev test prod; do
  bicep build-params "infra/parameters/main.$env.bicepparam" \
    --outfile "$out/$env.json"
done
```

Inspect the compiled template for a storage-account extension-resource ID whose
GUID includes the scope-kind discriminator. Deploy through protected main, verify
narrow grants, and only then delete historical resource-group grants.
