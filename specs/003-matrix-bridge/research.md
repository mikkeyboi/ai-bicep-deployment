# Research — 003 Matrix Bridge

## D1. Homeserver: continuwuity (vs Synapse, Dendrite, conduwuit)

**Decision**: continuwuity.

**Why**:
- conduwuit (the previous fork) was archived; continuwuity is the active
  community continuation by ex-conduwuit contributors, with weekly tags and
  CVE patching (current release `v0.5.5`, ratified 2026-05).
- Rust single binary, embedded RocksDB → **no Postgres needed**. Saves one
  Azure resource and ~$15/mo of credits.
- Memory footprint ~50–150 MB idle vs Synapse's ~1 GB; cheaper on ACA
  consumption.
- Matches the "private island" use case (no federation, 1–3 users).
- Mature container distribution at
  `forgejo.ellis.link/continuwuation/continuwuity` with multi-arch images
  and stable release tags.

**Trade-off**: less ecosystem tooling than Synapse (e.g., mautrix bridges
have more polish on Synapse). Acceptable — bridges are out of scope.

**Pinned tag**: `v0.5.5` (latest stable as of 2026-05). The `-maxperf`
variants are heavier-optimised builds; not needed for personal use.

## D2. Compute: ACA multi-container app (sidecar pattern)

**Decision**: single Container App with two containers:
1. `continuwuity` — listens on `:8008`
2. `cloudflared` — runs the tunnel

**Why**:
- Containers in the same ACA app share the loopback network (`localhost`),
  so cloudflared can target `http://localhost:8008`. No service mesh, no
  internal DNS, no extra ports.
- One revision, one scaling unit, one Azure Files mount — operationally
  simplest.
- Cloudflare Tunnel is the only public-facing path; ACA ingress can be
  configured `external: false`. Defense in depth.

**Rejected alternatives**:
- **Two separate ACA apps** (homeserver + tunnel) — would require an
  internal ingress URL and DNS coupling. Strictly worse.
- **App Service container** — no scale-to-zero, ~$13/mo idle, sidecars are
  recent and clunkier. Loses on every dimension here.
- **VM** — patching, TLS, monitoring overhead. Not worth it for a personal
  bridge.

## D3. Persistence: Azure Files share on the existing storage account

**Decision**: extend the existing storage module's account by adding a
fileServices/default/shares child. Mount it at `/var/lib/continuwuity`
inside the continuwuity container.

**Why**:
- ACA's native persistent storage is Azure Files (SMB or NFS). The existing
  workload storage account is already deployed and tagged correctly.
- RocksDB on SMB works fine for single-instance writers (we run one
  replica), and the share's data is encrypted at rest by the storage
  account's encryption settings.
- No new resource type to think about — Files share is a child of an
  account that already exists.

**Rejected**:
- **Azure Disks** — not supported by ACA managed environments today
  (requires AKS or VMs).
- **A dedicated storage account for Matrix** — gains isolation but doubles
  cost and adds one more thing to name/secure. Not warranted.

**Mount path**: `/var/lib/continuwuity` (verified from continuwuity's
official Docker compose docs at https://continuwuity.org/deploying/docker
— the documented `CONTINUWUITY_DATABASE_PATH` and recommended volume
mount).

**Storage key handling**: ACA's `Microsoft.App/managedEnvironments/storages`
resource requires the storage account key inline. `listKeys()` is invoked
inside the environment module (allowed — not exposed as an output).

## D4. Ingress: internal-only ACA, Cloudflare Tunnel as the only door

**Decision**: ACA ingress `external: false`. Cloudflare Tunnel hostname
`matrix.<operator-domain>` (parameterised via `MATRIX_HOSTNAME`; never committed) routes through
the cloudflared sidecar to `http://localhost:8008`.

**Why**:
- ACA's external ingress would expose a public
  `<app>.<envid>.<region>.azurecontainerapps.io` hostname. We don't want
  any path to continuwuity that bypasses Cloudflare's edge / Access policy.
- Cloudflare provides free managed TLS, DDoS protection, and (optionally)
  Cloudflare Access policies for additional auth before the request even
  hits Azure.
- The tunnel token is the only credential needed to wire it up; no DNS
  manipulation in Bicep (Cloudflare DNS is auto-managed by the tunnel).

## D5. Where the hostname lives

**Decision**: GitHub Environment Variable `MATRIX_HOSTNAME` on the `dev`
(and later `test`/`prod`) environment. Passed to deploy via:
- CI: `${{ vars.MATRIX_HOSTNAME }}` →
  `MATRIX_HOSTNAME=... az deployment sub ...`
- Local: `scripts/deploy.ps1 -MatrixHostname matrix.<your>.ca`

Inside the paramfile, `matrixHostname:
readEnvironmentVariable('MATRIX_HOSTNAME', '')` reads the value at compile
time. `main.bicep` asserts non-empty when `enableMatrix=true`.

**Why**: keeps the operator's real-name domain out of every tracked
file. Privacy grep enforces this.

## D6. Cloudflare tunnel token storage

**Decision**: Azure Key Vault secret `cloudflare-tunnel-token` on the
existing `kv-aio-dev-eus2-npnga`. Referenced by ACA via secret reference:

```bicep
secrets: [
  {
    name: 'cloudflare-tunnel-token'
    keyVaultUrl: '${kvUri}secrets/cloudflare-tunnel-token'
    identity: workloadMiResourceId
  }
]
```

ACA pulls the secret at revision-create time using the workload UAMI
(already has `Key Vault Secrets User` from feature 002).

**Why**:
- Zero-trust: no env var literal, no repo presence, no CI variable
  containing the token.
- Operator-managed lifecycle: rotate by overwriting the KV secret and
  restarting the ACA revision. No code change.

## D7. Image tag pins

| Container | Image | Tag | Source |
| --- | --- | --- | --- |
| continuwuity | `forgejo.ellis.link/continuwuation/continuwuity` | `v0.5.5` | Latest stable release as of 2026-05 |
| cloudflared | `docker.io/cloudflare/cloudflared` | `2026.3.0` | Latest semver tag on Docker Hub |

Both are exposed as parameters so future bumps are paramfile-only.
