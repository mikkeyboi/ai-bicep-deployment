"""Authenticating MCP gateway in front of Azure MCP Server (feature 016).

Claude (or any MCP client) talks to this gateway over Streamable HTTP. The
gateway is an OAuth 2.1 authorization server for the client (DCR, CIMD, S256
PKCE, refresh rotation) and delegates the actual sign-in to Microsoft Entra
ID. Every MCP request is then proxied to Azure MCP Server, which runs as a
sidecar on 127.0.0.1 in the same Container App replica. The gateway also
serves its own foundry_* tools (foundry_tools.py) for model deployments and
agents, running as the Azure MCP Server identity.

Security properties:
- Entra sign-in is single-tenant, and the enterprise app requires an
  assignment, so only assigned principals can complete sign-in at all.
- The gateway re-checks the signed-in principal's object ID against
  ALLOWED_PRINCIPAL_IDS on every request (fail closed).
- The user's Entra access token (audience = this app, scope
  Mcp.Tools.ReadWrite) is forwarded to Azure MCP Server, which validates it
  again with its own incoming auth. The client's gateway-issued token is
  never forwarded.
- No client secret exists: the gateway authenticates to Entra with a
  managed-identity client assertion via a federated identity credential.
- OAuth state (client registrations, encrypted upstream tokens) lives in
  Azure Table Storage, Fernet-encrypted with a key derived from a Key Vault
  secret, so connections survive restarts and revisions.
"""

from __future__ import annotations

import base64
import logging
import os
from typing import Any

import httpx2
from azure.identity.aio import ManagedIdentityCredential
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from key_value.aio.stores.azure_tables import AzureTablesSanitizationStrategy, AzureTablesStore
from key_value.aio.wrappers.encryption import FernetEncryptionWrapper
from starlette.requests import Request
from starlette.responses import PlainTextResponse

from fastmcp.client.transports import StreamableHttpTransport
from fastmcp.server import create_proxy
from fastmcp.server.auth import AccessToken
from fastmcp.server.auth.oauth_proxy.upstream import AsyncOAuth2Client
from fastmcp.server.auth.providers.azure import AzureProvider
from fastmcp.server.dependencies import get_access_token
from fastmcp.server.providers.proxy import ProxyClient
from fastmcp.server.transforms.visibility import Visibility

from foundry_tools import FoundryClient, register_foundry_tools

logger = logging.getLogger("azure_mcp_gateway")

# Scope Azure MCP Server requires on delegated inbound tokens.
MCP_SCOPE = "Mcp.Tools.ReadWrite"
# Audience Entra expects on a managed-identity federated client assertion.
TOKEN_EXCHANGE_SCOPE = "api://AzureADTokenExchange/.default"
UPSTREAM_TIMEOUT_SECONDS = 30.0

# Azure MCP tools hidden from clients: `foundry` proxies Microsoft's hosted
# Foundry MCP server, which rejects managed-identity tokens (the gateway's own
# foundry_* tools replace it), and `azd` needs a CLI the container lacks.
HIDDEN_BACKEND_TOOLS = {"foundry", "azd"}

# Redirect URIs the gateway will accept from MCP clients: the hosted Claude
# apps, plus loopback on any port for Claude Code and other native clients.
ALLOWED_CLIENT_REDIRECT_URIS = [
    "https://claude.ai/api/mcp/auth_callback",
    "https://claude.com/api/mcp/auth_callback",
    "http://localhost:*",
    "http://127.0.0.1:*",
]


def _env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable {name}")
    return value


def _derive_key(master: bytes, purpose: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=purpose).derive(master)


class _AssertionOAuthClient(AsyncOAuth2Client):
    """Upstream token client that authenticates with a managed-identity assertion."""

    def __init__(self, client_id: str, credential: ManagedIdentityCredential) -> None:
        # "none" makes the base class send client_id in the body; the
        # assertion is added per request below.
        super().__init__(
            client_id=client_id,
            token_endpoint_auth_method="none",
            timeout=UPSTREAM_TIMEOUT_SECONDS,
        )
        self._credential = credential

    async def _request_token(self, url: str, data: dict[str, Any]) -> dict[str, Any]:
        assertion = await self._credential.get_token(TOKEN_EXCHANGE_SCOPE)
        data["client_assertion_type"] = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        data["client_assertion"] = assertion.token
        return await super()._request_token(url, data)


class GatewayAuthProvider(AzureProvider):
    """AzureProvider with secretless upstream auth and a principal allowlist."""

    def __init__(
        self,
        *,
        assertion_credential: ManagedIdentityCredential,
        allowed_principal_ids: frozenset[str],
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self._assertion_credential = assertion_credential
        self._allowed_principal_ids = allowed_principal_ids

    def _create_upstream_oauth_client(self) -> AsyncOAuth2Client:
        return _AssertionOAuthClient(self._upstream_client_id, self._assertion_credential)

    async def load_access_token(self, token: str) -> AccessToken | None:  # type: ignore[override]
        access = await super().load_access_token(token)
        if access is None:
            return None
        principal_id = (access.claims or {}).get("oid")
        if principal_id not in self._allowed_principal_ids:
            logger.warning("rejected token for principal outside the allowlist: %s", principal_id)
            return None
        return access


class _ForwardUserToken(httpx2.Auth):
    """Send the signed-in user's Entra access token to Azure MCP Server."""

    def auth_flow(self, request: httpx2.Request):
        access = get_access_token()
        if access is None:
            raise RuntimeError("no authenticated user on this request")
        request.headers["Authorization"] = f"Bearer {access.token}"
        yield request


def build_app():
    tenant_id = _env("AZURE_TENANT_ID")
    client_id = _env("ENTRA_CLIENT_ID")
    base_url = _env("PUBLIC_BASE_URL").rstrip("/")
    backend_url = _env("AZURE_MCP_URL")
    identity_client_id = _env("GATEWAY_IDENTITY_CLIENT_ID")
    master_key = base64.b64decode(_env("GATEWAY_MASTER_KEY"))
    if len(master_key) < 32:
        raise RuntimeError("GATEWAY_MASTER_KEY must decode to at least 32 bytes")
    allowed = frozenset(p.strip() for p in _env("ALLOWED_PRINCIPAL_IDS").split(",") if p.strip())
    if not allowed:
        raise RuntimeError("ALLOWED_PRINCIPAL_IDS is empty")

    credential = ManagedIdentityCredential(client_id=identity_client_id)
    storage = FernetEncryptionWrapper(
        AzureTablesStore(
            account_name=_env("STORAGE_ACCOUNT_NAME"),
            endpoint=_env("STORAGE_TABLE_ENDPOINT").rstrip("/"),
            credential=credential,
            table_name=_env("STORAGE_TABLE_NAME"),
            # CIMD client IDs are URLs, and '/', '\', '#', '?' are illegal in
            # Table keys: such keys are stored under a stable SHA-256 instead.
            collection_sanitization_strategy=AzureTablesSanitizationStrategy(),
            key_sanitization_strategy=AzureTablesSanitizationStrategy(),
        ),
        fernet=Fernet(base64.urlsafe_b64encode(_derive_key(master_key, b"oauth-storage"))),
    )

    auth = GatewayAuthProvider(
        assertion_credential=credential,
        allowed_principal_ids=allowed,
        client_id=client_id,
        tenant_id=tenant_id,
        required_scopes=[MCP_SCOPE],
        base_url=base_url,
        allowed_client_redirect_uris=ALLOWED_CLIENT_REDIRECT_URIS,
        client_storage=storage,
        jwt_signing_key=_derive_key(master_key, b"jwt-signing"),
        # Entra v2 rejects the RFC 8707 resource parameter; scopes carry the audience.
        forward_resource=False,
    )

    backend = ProxyClient(
        StreamableHttpTransport(backend_url, auth=_ForwardUserToken()),
        forward_incoming_headers=False,
    )
    mcp = create_proxy(backend, name="Azure MCP", auth=auth)
    mcp.add_transform(Visibility(False, names=HIDDEN_BACKEND_TOOLS, components={"tool"}))
    register_foundry_tools(
        mcp,
        FoundryClient(
            ManagedIdentityCredential(client_id=_env("FOUNDRY_IDENTITY_CLIENT_ID")),
            subscription_id=_env("AZURE_SUBSCRIPTION_ID"),
            arm_url=_env("AZURE_RESOURCE_MANAGER_URL"),
        ),
    )

    @mcp.custom_route("/healthz", methods=["GET"])
    async def healthz(_: Request) -> PlainTextResponse:
        return PlainTextResponse("ok")

    return mcp.http_app(path="/mcp")


if __name__ == "__main__":
    import uvicorn

    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
    uvicorn.run(
        build_app(),
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8000")),
        proxy_headers=True,
        forwarded_allow_ips="*",
    )
