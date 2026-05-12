# Quickstart — 003 Matrix Bridge

Operator runbook for going from zero to a working private Matrix
homeserver reachable at `https://<your-hostname>`.

## Prereqs

- Feature 002 deployed (Foundry stack already in `rg-aio-dev-eus2`).
- A domain on Cloudflare DNS (e.g. `<yourdomain>.ca`).
- Cloudflare Zero Trust account (free plan is fine).

## One-time setup (operator, ~10 min)

### 1. Create the Cloudflare Tunnel

1. https://one.dash.cloudflare.com → **Networks → Tunnels → Create a
   tunnel**.
2. Connector type: **Cloudflared**.
3. Name it (e.g. `aio-matrix-dev`). Click **Save tunnel**.
4. On the "Install and run a connector" screen: **copy the token** (the
   long base64 string in the install commands). Don't run those commands —
   ACA will run cloudflared for you.
5. Click **Next** → on the **Public Hostnames** step:
   - Subdomain: `matrix`
   - Domain: `<yourdomain>.ca`
   - Type: `HTTP`
   - URL: `localhost:8008`
6. **Save tunnel**. Cloudflare creates a CNAME record automatically.

### 2. Stash the tunnel token in Key Vault

```pwsh
az keyvault secret set `
  --vault-name kv-aio-dev-eus2-npnga `
  --name cloudflare-tunnel-token `
  --value "<paste the token here>"
```

The token only leaves your shell once. Don't echo it. Don't commit it.

### 3. Set `MATRIX_HOSTNAME` on the GitHub `dev` environment

```pwsh
gh variable set MATRIX_HOSTNAME --env dev --body "matrix.<yourdomain>.ca"
```

### 4. Deploy

CI (preferred): merge to `main`; the `deploy` workflow runs automatically.

Local:
```pwsh
./scripts/deploy.ps1 `
  -Environment dev `
  -Subscription <sub> `
  -Tenant <tenant> `
  -MatrixHostname matrix.<yourdomain>.ca
```

### 5. Verify

- `https://matrix.<yourdomain>.ca` should return continuwuity's JSON
  endpoint listing (`{"server":...}`).
- Element web (https://app.element.io) → "Edit" homeserver → enter
  `https://matrix.<yourdomain>.ca` → **Sign in / Register**.
- The first account created is automatically promoted to admin by
  continuwuity (open-registration is off, but the first admin is set via
  the registration token printed in container logs on first start).

### 6. Create the bot user and extract its access token

1. In Element, while logged in as the admin: **Settings → Security &
   Privacy → Sessions** for the *admin* will show its token (or use
   `/devtools` to see it).
2. To create `@hermes`: open Element → registration with the admin token
   (continuwuity exposes a registration admin command in the
   `!admin` room — DM yourself `!admin help` once logged in).
3. After `@hermes` exists, log into Element as `@hermes` in a private
   browser, go to **Settings → Help & About → Advanced → Access Token**,
   copy the value. **That token is what Hermes consumes.**

### 7. Wire Hermes / OpenClaw

```
homeserver_url = https://matrix.<yourdomain>.ca
user_id        = @hermes:matrix.<yourdomain>.ca
access_token   = <token from step 6>
```

## Day-2 ops

- **Rotate the tunnel token**: Cloudflare dashboard → rotate →
  `az keyvault secret set ...` → `az containerapp revision restart
  --name <app> --resource-group <rg>`.
- **Bump continuwuity**: change `continuwuityImage` in
  `main.dev.bicepparam` to the new pinned tag; CI redeploys.
- **Back up RocksDB**: snapshot the Azure Files share periodically
  (`az storage file download-batch` or Azure Backup).

## Notes

- `server_name` (the hostname) is permanent for a given database. Changing
  hostnames requires wiping the share. Plan accordingly.
- Federation is intentionally disabled. The homeserver won't talk to
  matrix.org / other servers.
