# Plan — 016 Azure MCP connector

## Architecture

```
Claude (claude.ai / Desktop / Code)
   │  HTTPS  https://ca-aio-dev-eus2-mcp.<env-domain>/mcp
   ▼
ACA ingress (external, TLS) ──► gateway :8000   (apps/azure-mcp-gateway)
                                  │ OAuth AS for Claude (DCR/CIMD/PKCE)
                                  │ sign-in delegated to Entra (FIC, no secret)
                                  │ oid allowlist on every request
                                  │ state → Table Storage (Fernet, KV-derived key)
                                  ▼ http://127.0.0.1:5008, Bearer <user Entra token>
                               azure-mcp :5008  (mcr …/azure-mcp:4.0.0-beta.4)
                                  │ validates token (aud, iss, scp=Mcp.Tools.ReadWrite)
                                  ▼ managed identity id-…-mcp-srv (Reader @ subscription)
                               Azure Resource Manager / data planes
```

## Files

| Path | Purpose |
| --- | --- |
| `infra/azure-mcp/main.bicep` | RG-scope entry point for this stack |
| `infra/parameters/azure-mcp.dev.bicepparam` | dev config (image pins, roles, sizing) |
| `infra/modules/azure-mcp/entra-app.bicep` | Graph: app, SP, FIC, assignments, consent |
| `infra/modules/azure-mcp/environment.bicep` | external Consumption CAE |
| `infra/modules/azure-mcp/container-app.bicep` | gateway + azure-mcp containers |
| `infra/modules/role-assignment/subscription.bicep` | subscription-scope RBAC (shares the role table) |
| `infra/modules/role-assignment/main.bicep` | + `AcrPull`, `Storage Table Data Contributor`; + `containerRegistry` / `keyVaultSecret` scopes |
| `apps/azure-mcp-gateway/` | gateway source, Dockerfile, hashed lock |
| `scripts/deploy-azure-mcp.sh` | seed master key → build image → validate → what-if → create |

## Decisions

- **Gateway instead of Entra-as-AS.** Claude can't use Entra directly for a
  `*.azurecontainerapps.io` URL (AADSTS9010010, and no DCR). FastMCP's
  `AzureProvider` already implements the OAuth proxy, strips the `resource`
  parameter for Entra v2, and supports CIMD.
- **Keep Azure MCP Server's incoming auth on.** The gateway forwards the
  user's Entra token, which Azure MCP Server checks itself, so the backend
  stays protected even if gateway authorization regressed.
- **Managed identity, not On-Behalf-Of, for outbound.** Least privilege
  (`Reader`) regardless of the operator's own Owner role. Read-only by
  default; widening it is a two-line paramfile change.
- **Secretless.** A federated credential on the app trusts the gateway's
  managed identity, so there's no client secret to rotate or leak. The only
  secret is the gateway's own master key in Key Vault, readable by that
  identity alone.
- **Separate public CAE.** The existing CAE is internal (VNet ILB) with
  Cloudflare as its only public path. Routing a second hostname through that
  tunnel would put the operator's domain in play and couple the two
  services. A Consumption environment costs nothing on its own.
- **minReplicas 1.** A scale-from-zero cold start measured about 56 s
  (two image pulls plus .NET start), far past Claude's 10-second discovery
  timeout, so one replica stays warm. At the Consumption idle rate that's
  roughly USD 15 per month.

## Complexity Tracking

| Principle | Deviation | Why | Simpler alternative rejected because |
| --- | --- | --- | --- |
| IV (one entry point per scope) | Second RG-scope entry point `infra/azure-mcp/main.bicep` | It declares Microsoft Graph resources (app registration, SP, FIC, app-role assignments, consent grants). Deploying them needs directory privileges | Folding it into `infra/main.bicep` would require granting the GitHub OIDC principal Graph application permissions (`Application.ReadWrite.OwnedBy`, `AppRoleAssignment.ReadWrite.All`), contrary to Principle III's least privilege for CI on a public repo. |
| VI (deploy only from CI after merge) | Deployed by the operator via `scripts/deploy-azure-mcp.sh` | Same reason: the deploying identity needs directory rights | — validate.yml still lints and builds this entry point on every PR. |

## Rollback

`az containerapp delete -n ca-aio-dev-eus2-mcp -g <rg>` stops all exposure.
Full removal: delete the app, the `cae-aio-dev-eus2-mcp` environment, both
`id-aio-dev-eus2-mcp-*` identities (their role assignments go with them), and
the Entra app `aio-dev Azure MCP connector`. No existing resource is modified
by this stack.
