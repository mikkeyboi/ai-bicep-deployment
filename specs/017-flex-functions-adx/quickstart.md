# Quickstart — 017

## Validate locally (no Azure needed)

```bash
export TMPDIR=~/.cache/bigtmp PATH="$HOME/.local/bin:$PATH"
scratch=$(mktemp -d)
bicep build infra/main.bicep --outdir "$scratch"
for e in dev test prod; do
  bicep build-params infra/parameters/main.$e.bicepparam --outfile "$scratch/p_$e.json"
done
```

All four must exit 0. Building **test and prod** is the point: it proves the new optional
blocks did not break the environments that omit them.

Confirm the wiring actually resolved:

```bash
grep -o '"FC1"\|"FlexConsumption"\|Microsoft.Kusto/clusters' "$scratch/main.json" | sort | uniq -c
grep -c listKeys "$scratch/main.json"   # must not exceed the pre-existing count (4, all in modules/matrix)
```

## Deploy

Merging to `main` with changes under `infra/**` triggers `deploy.yml` against dev
automatically. To run it deliberately:

```bash
gh workflow run deploy.yml -f environment=dev
gh run watch <run-id> --exit-status
```

## After deploying: the two data-plane steps

ARM cannot do these. From the consuming repo (`mechinterp/aiplatform`):

```bash
# 1. tables, functions, dashboard queries
python scripts/apply_kql.py --cluster "$ADX_CLUSTER_URI" --database hvac

# 2. ingestor grant for the function's identity (principal id is a deployment output)
python scripts/grant_adx_ingestor.py --cluster "$ADX_CLUSTER_URI" --database hvac \
    --principal-id "$(az deployment sub show -n <deployment> \
        --query properties.outputs.functionAppPrincipalId.value -o tsv)"
```

## Retiring the old Linux Consumption app

Only after the Flex app is verified writing to ADX:

```bash
az functionapp delete -g rg-aio-dev-eus2 -n <old-app>
az appservice plan delete -g rg-aio-dev-eus2 -n EastUS2LinuxDynamicPlan --yes
```

The old app is not in the template, so an incremental deployment will never remove it.
Deleting it is a deliberate act, and doing it before the new app is proven leaves the
workflow with no trigger at all.
