# Quickstart — Azure MCP connector

## Prerequisites

- The main stack (`infra/main.bicep`) is deployed for the environment.
- `az login` as a user who can create app registrations and grant tenant-wide
  consent (Application Administrator or Global Administrator), assign RBAC at
  subscription scope (Owner or User Access Administrator), and write Key Vault
  secrets.
- `bicep`, `python3`, `openssl` on PATH. Docker isn't needed: the gateway
  image builds in ACR.

## Deploy

```bash
scripts/deploy-azure-mcp.sh --environment dev \
  --subscription <YOUR_SUBSCRIPTION_ID> --tenant <YOUR_TENANT_ID> --what-if
scripts/deploy-azure-mcp.sh --environment dev \
  --subscription <YOUR_SUBSCRIPTION_ID> --tenant <YOUR_TENANT_ID>
```

The script prints `MCP server URL : https://ca-aio-dev-eus2-mcp.<domain>/mcp`.
To allow more people than yourself, export a comma-separated list of Entra
object IDs as `AZURE_MCP_ALLOWED_PRINCIPAL_IDS` before running it.

## Add the connector in Claude

1. claude.ai → **Settings → Connectors → Add custom connector**.
2. Name: `Azure`. URL: the MCP server URL above.
3. Leave **Advanced settings** (OAuth client ID/secret) empty. Claude
   registers itself with the gateway.
4. **Connect** → approve the gateway's consent page → sign in with your Entra
   account. You return to Claude, connected.

Claude Code: `claude mcp add --transport http azure <MCP server URL>`, then
`/mcp` to sign in.

## Verify

```bash
curl -si -X POST <MCP server URL> -H 'content-type: application/json' -d '{}' | grep -i 'HTTP/\|www-authenticate'
# HTTP/2 401 + WWW-Authenticate: Bearer ... resource_metadata="https://.../.well-known/oauth-protected-resource/mcp"
```

Ask Claude: "List my Azure resource groups."

## Updating

Every change goes through the same command, `scripts/deploy-azure-mcp.sh`.
It shows the what-if before applying, then rolls a new revision: the old one
serves until the new one is healthy, and Claude stays connected because OAuth
state lives in Table Storage.

| Change | Edit | Then |
| --- | --- | --- |
| Azure MCP Server version | `azureMcpImage` in `azure-mcp.<env>.bicepparam` (the script prints newer MCR tags) | run the script |
| Gateway code | `apps/azure-mcp-gateway/app.py` | run the script (the image tag is a content hash, so it rebuilds automatically) |
| Gateway dependencies | `requirements.in`, then `uv pip compile --python-version 3.12 --generate-hashes requirements.in -o requirements.txt` | run the script |
| Permissions / sizing | `subscriptionRoles`, `readOnly`, CPU/memory in the paramfile | run the script |

## Change access

- **Roles**: `subscriptionRoles` (subscription scope) and `resourceGroupRoles`
  (workload resource group) in `azure-mcp.<env>.bicepparam`. dev has
  Reader everywhere, plus Cognitive Services Contributor and Foundry User on
  the resource group, with `readOnly: false`. Avoid roles that can write role
  assignments.
- **Revoke a user**: remove them from `AZURE_MCP_ALLOWED_PRINCIPAL_IDS` and
  redeploy. Their existing tokens fail the gateway allowlist immediately after
  the new revision starts. Removing their Entra assignment for the enterprise
  app also blocks new sign-ins.

## Troubleshooting

- Logs: `az containerapp logs show -n ca-aio-dev-eus2-mcp -g <rg> --container gateway`
  (or `--container azure-mcp`).
- "Couldn't reach the MCP server": check the revision is running
  (`az containerapp revision list ...`). With `minReplicas: 0` a cold start
  takes about a minute, longer than Claude waits, so dev keeps `minReplicas: 1`.
- `AADSTS50105` at sign-in: the account isn't assigned to the enterprise app.
  Add its object ID to the allowed list and redeploy.
