# Feature 003 — Matrix Bridge for Autonomous Agents

**Status**: Draft → Plan → Implementation
**Constitution**: v1.2.0 (no amendment required; existing principles cover this)

## Problem

Mike runs autonomous agents (OpenClaw, Hermes) locally on his Mac/Windows
machines. He needs a private, always-on chat surface they can connect to as
clients so he can interact with them from any device. The surface must be
hosted on Azure (consumption billing, fits this repo's purpose) without
exposing a public `*.azurecontainerapps.io` endpoint, and without leaking the
operator's real-name domain into the public repo.

## User stories

### US1 — Operator deploys a private Matrix homeserver via CI/CD (P1)
**Given** a new feature branch with a `MATRIX_HOSTNAME` GitHub Environment
variable set on `dev`, **when** the deploy workflow runs, **then** an Azure
Container Apps app comes up running continuwuity behind a Cloudflare Tunnel,
with ACA ingress set to internal-only and the tunnel as the only ingress
path.

### US2 — Operator logs in via Element to create the @hermes bot user (P1)
**Given** continuwuity is running and reachable at
`https://<MATRIX_HOSTNAME>`, **when** the operator visits Element web with
that homeserver URL, **then** they can register the first user, create the
`@hermes` bot, and extract a long-lived access token.

### US3 — Agents authenticate from Mac/Windows and exchange messages (P2)
**Given** the access token from US2, **when** Hermes or OpenClaw is
configured with `homeserver_url=https://<MATRIX_HOSTNAME>`, the user ID,
and that token, **then** the agent can send/receive Matrix messages.

### US4 — Persistent state survives container restarts (P1)
**Given** continuwuity has accepted messages and built up RocksDB state,
**when** the container revision is replaced (image bump, redeploy), **then**
the next container instance loads the same database from the Azure Files
mount and all rooms/messages persist.

## Functional requirements

- **FR-001**: Homeserver image is continuwuity, pinned to a specific tag
  (not `latest` or `main`).
- **FR-002**: The continuwuity container's data directory
  (`/var/lib/continuwuity`) is mounted from an Azure Files share on the
  existing storage account.
- **FR-003**: Federation is disabled (`allow_federation = false`).
- **FR-004**: Open registration is disabled
  (`allow_registration = false`).
- **FR-005**: Update-check phone-home is disabled
  (`allow_check_for_updates = false`).
- **FR-006**: ACA ingress is internal-only — no public ACA hostname.
- **FR-007**: A `cloudflare/cloudflared` sidecar container in the same ACA
  app proxies inbound traffic from the Cloudflare edge to
  `http://localhost:8008` (continuwuity).
- **FR-008**: The Cloudflare tunnel token is stored in the existing Key
  Vault under secret `cloudflare-tunnel-token` and referenced by ACA via
  Key Vault secret reference (not env-var literal). The workload UAMI is
  granted `Key Vault Secrets User` on the vault (already in place from 002).
- **FR-009**: The Matrix hostname (`MATRIX_HOSTNAME`) is parameterized:
  passed via GitHub Environment Variable in CI and via `-MatrixHostname`
  on `scripts/deploy.ps1` locally. It MUST NOT appear in any tracked file
  as a default value.
- **FR-010**: The deployment is gated by a feature flag (`enableMatrix`).
  Default `false` in `test`/`prod`, `true` in `dev`.
- **FR-011**: The cloudflared sidecar is gated by a feature flag
  (`enableCloudflareTunnel`), default `true` when `enableMatrix=true`. This
  allows a first-pass deploy of continuwuity alone, ahead of setting the KV
  secret, if the operator prefers an incremental rollout.
- **FR-012**: Diagnostic settings on the Container Apps Environment route
  to the existing Log Analytics workspace.

## Non-functional requirements

- **NFR-001**: Image tags are pinned (no `:latest` / no `:main`).
- **NFR-002**: Tunnel token never appears in repo, env-var literal, or CI
  logs.
- **NFR-003**: Privacy grep for the operator's domain, tenant ID, subscription ID,
  any gmail address, and tunnel-token shapes returns zero hits over the
  tracked tree before any commit.

## Success criteria

- `bicep lint`, `bicep build`, `az deployment sub validate`, and
  `az deployment sub what-if` all succeed for the dev paramfile with
  `MATRIX_HOSTNAME` set in the local environment.
- `gitleaks detect` passes on the working tree and on the committed history.
- Operator can run `az keyvault secret set --vault-name <kv> --name
  cloudflare-tunnel-token --value <token>`, deploy, and reach
  `https://matrix.<operator-domain>` from a browser without any further config.

## Edge cases

- **Token rotation**: operator rotates the tunnel token in Cloudflare,
  re-runs `az keyvault secret set`, and triggers a restart of the ACA
  revision (`az containerapp revision restart`). No redeploy needed.
- **Container restart preserving state**: RocksDB is on the Azure Files
  mount; container restarts must not lose data.
- **Hostname change**: continuwuity bakes `server_name` into its database
  on first start; changing it requires a wipe. Documented in quickstart.
- **`MATRIX_HOSTNAME` missing in CI**: deployment must fail loudly at
  `validate` time (empty string in paramfile triggers an explicit guard in
  `main.bicep`), not silently deploy an unreachable app.
- **Tunnel KV secret missing on first deploy**: if `enableCloudflareTunnel`
  is true and the secret is absent, ACA deployment fails. Operator may
  set `enableCloudflareTunnel=false` for a first pass to verify
  continuwuity comes up, then flip it to true after setting the secret.

## Out of scope (deliberate)

- Federation with other Matrix homeservers.
- Bridges to Discord/Slack/Telegram (mautrix-*) — separate future feature.
- Matrix-side admin automation (creating users / extracting tokens via API)
  — handled manually via Element web for now.
- Public registration / signup flows.
- Custom domain for ACA's own hostname (the only public hostname is
  Cloudflare's; ACA stays internal).
