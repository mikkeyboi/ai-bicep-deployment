# Feature 016 — Azure MCP Server as an authenticated Claude connector

**Status**: Implementation
**Constitution**: v1.2.0 (one Complexity Tracking entry; see plan.md)

## Problem

The operator wants to work with the subscription's resources from Claude
(claude.ai, Desktop, mobile, Claude Code) through Microsoft's Azure MCP
Server. Claude reaches custom connectors over the public internet, so the
server needs a public HTTPS endpoint. It must not be usable by anyone except
the operator, and it must not widen what an internet-facing component can do
in the subscription.

Two constraints shape the design:

- Claude's OAuth client needs an authorization server with DCR or CIMD,
  S256 PKCE, and protected resource metadata whose `resource` equals the
  MCP URL. Entra ID can't fill that role directly: the MCP URL would have
  to be an Application ID URI, which Entra only allows on a verified
  domain, and `*.azurecontainerapps.io` isn't one (AADSTS9010010).
- Azure MCP Server's HTTP mode requires a valid Entra bearer token
  (scope `Mcp.Tools.ReadWrite`) on every request, which a Claude-issued
  token is not.

## User stories

### US1 — Operator adds the connector in Claude and signs in with Entra (P1)
**Given** the stack is deployed, **when** the operator adds the MCP URL as a
custom connector and clicks Connect, **then** Claude registers itself (DCR
or CIMD), the operator approves the gateway's consent page, signs in with
their Entra account, and the connector shows as connected. No client ID or
secret has to be entered in Claude.

### US2 — Claude uses Azure MCP tools against the subscription (P1)
**Given** a connected connector, **when** the operator asks Claude about
their Azure resources, **then** Claude calls Azure MCP Server tools
(resource groups, storage, monitor, ...), which run as a dedicated managed
identity with `Reader` on the subscription.

### US3 — Nobody else can use it (P1)
**Given** the public URL, **when** anyone who is not an allowed principal
tries to connect, **then** Entra refuses sign-in (assignment required), and
even a token minted for another tenant member is rejected by the gateway's
principal allowlist and again by Azure MCP Server's own token validation.

### US4 — Connections survive restarts (P2)
**Given** a connected connector, **when** the app scales to zero, restarts,
or rolls to a new revision, **then** Claude's existing tokens and client
registration keep working (no reconnect).

## Functional requirements

- **FR-001**: Azure MCP Server image `mcr.microsoft.com/azure-sdk/azure-mcp`
  pinned to `4.0.0-beta.4` (4.0.0 preferred, even in beta). Never `latest`.
- **FR-002**: Azure MCP Server runs with incoming auth ON (no
  `--dangerously-disable-http-incoming-auth`), bound to `127.0.0.1`, with
  `--outgoing-auth-strategy UseHostingEnvironmentIdentity` and `--read-only`
  by default.
- **FR-003**: A gateway sidecar (FastMCP 4.1.4 `AzureProvider`, OAuth proxy
  pattern) is the only ingress target. It serves RFC 9728 protected resource
  metadata, RFC 8414 AS metadata, DCR, CIMD, S256 PKCE and refresh rotation,
  and returns `401` + `WWW-Authenticate: Bearer resource_metadata=...` when no
  token is sent.
- **FR-004**: The gateway accepts client redirect URIs only for
  `https://claude.ai/api/mcp/auth_callback`,
  `https://claude.com/api/mcp/auth_callback` and loopback (any port).
- **FR-005**: The gateway forwards the user's **Entra** access token (never
  the client-facing gateway token) to Azure MCP Server.
- **FR-006**: The gateway rejects tokens whose `oid` is not in the allowed
  principal list (fail closed; the list is required at compile time).
- **FR-007**: No client secret exists. The gateway authenticates to Entra
  with a federated identity credential that trusts its user-assigned managed
  identity.
- **FR-008**: The Entra enterprise app requires assignment; only the allowed
  principals are assigned. Tenant-wide consent is granted for the app's own
  scope and `offline_access`, so sign-in shows no consent prompt.
- **FR-009**: Two user-assigned identities with disjoint permissions:
  - gateway: `AcrPull` on the registry, `Storage Table Data Contributor` on
    the storage account, and `Key Vault Secrets User` on its single secret.
  - Azure MCP Server: `subscriptionRoles` (default `Reader`) at
    subscription scope, plus `resourceGroupRoles` at the workload resource
    group. dev sets `Cognitive Services Contributor` (Foundry accounts,
    projects, model deployments) and `Foundry User` (inference, agents).
    Roles that can write role assignments are excluded on purpose.
- **FR-010**: OAuth state (client registrations, encrypted upstream tokens)
  persists in Azure Table Storage, Fernet-encrypted with a key derived (HKDF)
  from Key Vault secret `azure-mcp-gateway-master-key`. The JWT signing key
  is derived from the same secret.
- **FR-011**: The Container Apps environment is a separate external
  (public), Consumption-profile environment. The Matrix environment from
  feature 003 stays internal-only and untouched.
- **FR-012**: No tenant, subscription or object IDs, no hostnames and no
  emails in source. Allowed principals come from
  `$env:AZURE_MCP_ALLOWED_PRINCIPAL_IDS` (the deploy script defaults it to
  the signed-in operator).

## Known limitation: Foundry MCP tools

Azure MCP's `foundry` namespace proxies Microsoft's hosted Foundry MCP
server (`https://mcp.ai.azure.com`), which provides model deployment, agent
and evaluation tools. That server accepts the managed identity's token for
`initialize` / `tools/list`, but every tool call fails with an internal
server error: it expects a delegated user token (On-Behalf-Of). The same
identity can call the Foundry ARM and agents APIs directly (verified
2026-10-30), so this isn't an RBAC gap.

Resolution: the gateway hides that `foundry` tool (and `azd`, whose CLI the
container lacks) and serves its own Foundry tools (`foundry_tools.py`) as the
Azure MCP Server identity:

- **FR-013**: `foundry_list_accounts`, `foundry_list_models`,
  `foundry_get_quota`, `foundry_list_deployments`, `foundry_deploy_model`
  (refuses Marketplace-billed models, waits up to 90 s), and
  `foundry_delete_deployment` (ARM `2026-09-01`).
- **FR-014**: `foundry_list_agents`, `foundry_get_agent`,
  `foundry_create_or_update_agent` (prompt agents; a new version per call),
  `foundry_delete_agent`, and `foundry_run_agent` (Responses API with
  `agent_reference`; `previous_response_id` continues a conversation).
  Foundry agents API `v1`.
- **FR-015**: Read tools are annotated `readOnlyHint`, while deploy and
  delete tools are `destructiveHint`, so clients ask before running them.
  Deployment and agent names are validated before they reach a URL.
- **FR-016**: `foundry_list_image_deployments` (deployments with the
  `imageGenerations` capability, on any account) and `foundry_generate_image`
  (`image_tools.py`). The latter uses gpt-image-* via the OpenAI v1
  `images/generations` route and MAI-Image-* via `/mai/v1/images/generations`
  (both sides >= 768 px, <= 1,048,576 px). It returns 1–4 inline JPEG
  previews (<= 1024 px) plus read-only user-delegation SAS links (1–168 h,
  default 24 h) to full-resolution originals in the private
  `generated-images` container. The Azure MCP identity holds
  `Storage Blob Data Contributor` on that container only, plus
  `Storage Blob Delegator` on the account to sign the links.

## Out of scope

- On-Behalf-Of outbound auth (per-user Azure RBAC). The `UseOnBehalfOf`
  strategy is supported by Azure MCP Server and could replace the managed
  identity later; it needs extra delegated permissions and admin consent per
  downstream API.
- IP allowlisting on ingress: the operator's browser has to reach the OAuth
  endpoints from arbitrary networks.
- CI deployment of this stack (see plan.md, Complexity Tracking).
