# Quickstart: 004 East US Image Foundry

Operator runbook for the additive eastus image account. Assumes the
feature-002 stack is already deployed in eastus2.

## 0. Prereqs

- `az` CLI + `bicep` (the authoring env did not have them; CI installs
  the standalone bicep binary — see `.github/workflows/validate.yml`).
- `az login` to the operator's subscription/tenant.
- `cognitiveservices` extension: `az extension add -n cognitiveservices`.

## 1. Confirm model availability + versions in eastus

```bash
az cognitiveservices model list --location eastus \
  --query "[?contains(['gpt-image-2','MAI-Image-2.5'], name)].{name:name,format:format,version:version,sku:skus[0].name,cap:skus[0].capacity.default}" \
  -o table
```

- If `gpt-image-2` shows a dated version, pin it in
  `infra/parameters/main.dev.bicepparam` (replace `version: 'latest'`).
- If `MAI-Image-2.5` shows a version other than `2026-06-02`, update it.

## 2. Validate + what-if (no changes applied)

```pwsh
./scripts/deploy.ps1 -Environment dev `
  -Subscription <YOUR_SUBSCRIPTION_ID> -Tenant <YOUR_TENANT_ID> -WhatIf
```

Expect the what-if to **create** (additive):
- `aif-aio-dev-eus-<hash>` (eastus account)
- `…/projects/proj-aio-dev-eus`
- two deployments: `gpt-image-2`, `mai-image-2-5`
- a role assignment (Cognitive Services User) + a diagnostic setting

…and to leave the eastus2 account and its deployments **unchanged**.

## 3. Deploy

```pwsh
./scripts/deploy.ps1 -Environment dev `
  -Subscription <YOUR_SUBSCRIPTION_ID> -Tenant <YOUR_TENANT_ID> -Yes
```

## 4. Smoke check

```bash
ACCT=$(az cognitiveservices account list -g rg-aio-dev-eus2 \
  --query "[?location=='eastus'].name | [0]" -o tsv)   # name embeds -eus-
az cognitiveservices account deployment list -g rg-aio-dev-eus2 -n "$ACCT" -o table
```

> Note: the resource GROUP is still the primary one
> (`rg-aio-dev-eus2`), created at subscription scope by `main.bicep`.
> Only the *account* is in eastus. Confirm with `--query "[].location"`.

## 5. Use API-key auth (re-enabled on this account only)

Keys are NOT in source. Fetch at runtime:

```bash
KEY=$(az cognitiveservices account keys list -g rg-aio-dev-eus2 -n "$ACCT" \
  --query key1 -o tsv)
ENDPOINT=$(az cognitiveservices account show -g rg-aio-dev-eus2 -n "$ACCT" \
  --query properties.endpoint -o tsv)

# MAI image generation (api-key header):
curl -X POST "$ENDPOINT/mai/v1/images/generations" \
  -H "Content-Type: application/json" -H "api-key: $KEY" \
  -d '{"model":"mai-image-2-5","prompt":"a calm prairie at dawn","width":1024,"height":1024}'
```

> Do not paste `$KEY` into any tracked file, commit, PR comment, or CI
> log. Keep it in the shell session only.

## 6. Rollback

- Set `secondaryFoundry.enabled = false` (or remove the block) in the
  dev paramfile and redeploy → the eastus account + project +
  deployments are removed; eastus2 untouched.
- To revert just the key posture: set
  `secondaryFoundry.disableLocalAuth = true` and redeploy.
