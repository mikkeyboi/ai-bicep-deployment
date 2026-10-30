"""Foundry management tools served by the gateway itself (feature 016).

Azure MCP Server's `foundry` namespace proxies Microsoft's hosted Foundry MCP
server, which only works with delegated user tokens, so it can't run as this
deployment's managed identity. These tools cover the core lifecycle (model
deployments and prompt agents) against the public ARM and Foundry project
APIs instead. They run as the Azure MCP Server identity, so they're bounded
by the same RBAC: Cognitive Services Contributor + Foundry User on the
workload resource group, Reader elsewhere.
"""

from __future__ import annotations

import asyncio
import re
import time
from typing import Annotated, Any

import httpx2
from azure.identity.aio import ManagedIdentityCredential
from pydantic import Field

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError

ARM_SCOPE = "https://management.azure.com/.default"
FOUNDRY_SCOPE = "https://ai.azure.com/.default"
ARM_API_VERSION = "2026-09-01"
AGENTS_API_VERSION = "v1"
FOUNDRY_KINDS = {"AIServices", "OpenAI"}
ACCOUNT_CACHE_SECONDS = 300
DEPLOY_WAIT_SECONDS = 90
TERMINAL_STATES = {"Succeeded", "Failed", "Canceled"}

READ_ONLY = {"readOnlyHint": True, "openWorldHint": True}
CREATES = {"readOnlyHint": False, "destructiveHint": False, "openWorldHint": True}
DESTRUCTIVE = {"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True}

AccountName = Annotated[str, Field(description="Foundry account name (see foundry_list_accounts).")]
# Names that end up in URL paths: no '/', '?', '#' or '..' tricks.
NAME_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"
ProjectName = Annotated[
    str | None,
    Field(description="Foundry project name. Optional when the account has exactly one project."),
]


def _error_message(response: httpx2.Response) -> str:
    try:
        body = response.json()
    except ValueError:
        return response.text[:500]
    error = body.get("error", body) if isinstance(body, dict) else body
    if isinstance(error, dict):
        return f"{error.get('code', '')} {error.get('message', '')}".strip()
    return str(error)[:500]


class FoundryClient:
    """Thin REST client for ARM (control plane) and Foundry projects (data plane)."""

    def __init__(self, credential: ManagedIdentityCredential, subscription_id: str, arm_url: str) -> None:
        self._credential = credential
        self.subscription_id = subscription_id
        self._arm_url = arm_url.rstrip("/")
        self._http = httpx2.AsyncClient(timeout=60.0)
        self._accounts: dict[str, dict[str, Any]] = {}
        self._accounts_loaded_at = 0.0

    async def _request(self, method: str, url: str, scope: str, *, body: Any = None) -> Any:
        token = (await self._credential.get_token(scope)).token
        response = await self._http.request(
            method, url, json=body, headers={"Authorization": f"Bearer {token}"}
        )
        if response.status_code >= 400:
            path = url.split("?")[0].split(".com", 1)[-1]
            raise ToolError(f"{method} {path} failed ({response.status_code}): {_error_message(response)}")
        return response.json() if response.content else {}

    async def arm(self, method: str, path: str, *, body: Any = None) -> Any:
        separator = "&" if "?" in path else "?"
        url = f"{self._arm_url}{path}{separator}api-version={ARM_API_VERSION}"
        return await self._request(method, url, ARM_SCOPE, body=body)

    async def arm_list(self, path: str) -> list[dict[str, Any]]:
        page = await self.arm("GET", path)
        items = list(page.get("value", []))
        while next_link := page.get("nextLink"):
            page = await self._request("GET", next_link, ARM_SCOPE)
            items.extend(page.get("value", []))
        return items

    async def accounts(self, refresh: bool = False) -> dict[str, dict[str, Any]]:
        if refresh or time.monotonic() - self._accounts_loaded_at > ACCOUNT_CACHE_SECONDS:
            listed = await self.arm_list(
                f"/subscriptions/{self.subscription_id}/providers/Microsoft.CognitiveServices/accounts"
            )
            self._accounts = {a["name"]: a for a in listed if a.get("kind") in FOUNDRY_KINDS}
            self._accounts_loaded_at = time.monotonic()
        return self._accounts

    async def account(self, name: str) -> dict[str, Any]:
        accounts = await self.accounts()
        if name not in accounts:
            accounts = await self.accounts(refresh=True)
        if name not in accounts:
            raise ToolError(f"Foundry account '{name}' not found. Available: {', '.join(sorted(accounts)) or 'none'}")
        return accounts[name]

    async def project_endpoint(self, account_name: str, project: str | None) -> str:
        account = await self.account(account_name)
        projects = await self.arm_list(f"{account['id']}/projects")
        names = [p["name"].split("/")[-1] for p in projects]
        if project is None:
            if len(projects) != 1:
                raise ToolError(f"Account '{account_name}' has projects {names}; pass project.")
            chosen = projects[0]
        else:
            matches = [p for p, n in zip(projects, names) if n == project]
            if not matches:
                raise ToolError(f"Project '{project}' not found in '{account_name}'. Available: {names}")
            chosen = matches[0]
        endpoint = (chosen.get("properties", {}).get("endpoints") or {}).get("AI Foundry API")
        if not endpoint:
            raise ToolError(f"Project '{chosen['name']}' exposes no Foundry API endpoint.")
        return endpoint.rstrip("/")

    async def project_call(
        self, account: str, project: str | None, method: str, path: str, *, body: Any = None, versioned: bool = True
    ) -> Any:
        url = await self.project_endpoint(account, project) + path
        if versioned:
            url += f"?api-version={AGENTS_API_VERSION}"
        return await self._request(method, url, FOUNDRY_SCOPE, body=body)


def _squash(value: str) -> str:
    """Lowercase alphanumerics only: quota names spell models inconsistently (gpt4.1-mini vs gpt-4.1-mini)."""
    return re.sub(r"[^a-z0-9]", "", value.lower())


def _summarize_agent(agent: dict[str, Any]) -> dict[str, Any]:
    latest = (agent.get("versions") or {}).get("latest") or {}
    definition = latest.get("definition") or {}
    return {
        "name": agent.get("name"),
        "latest_version": latest.get("version"),
        "kind": definition.get("kind"),
        "model": definition.get("model"),
        "description": latest.get("description"),
        "metadata": latest.get("metadata") or {},
    }


def _response_text(response: dict[str, Any]) -> str:
    parts = []
    for item in response.get("output", []):
        if item.get("type") == "message":
            parts.extend(c.get("text", "") for c in item.get("content", []) if c.get("type") == "output_text")
    return "\n".join(p for p in parts if p)


def register_foundry_tools(mcp: FastMCP, client: FoundryClient) -> None:
    @mcp.tool(annotations=READ_ONLY)
    async def foundry_list_accounts() -> list[dict[str, Any]]:
        """List the subscription's Foundry (AIServices / Azure OpenAI) accounts and their projects."""
        accounts = await client.accounts(refresh=True)
        result = []
        for account in accounts.values():
            projects = await client.arm_list(f"{account['id']}/projects") if account.get("kind") == "AIServices" else []
            result.append({
                "name": account["name"],
                "resource_group": account["id"].split("/")[4],
                "location": account.get("location"),
                "kind": account.get("kind"),
                "projects": [p["name"].split("/")[-1] for p in projects],
            })
        return result

    @mcp.tool(annotations=READ_ONLY)
    async def foundry_list_models(
        account: AccountName,
        name_contains: Annotated[str | None, Field(description="Case-insensitive filter on model name.")] = None,
        include_deprecated: Annotated[bool, Field(description="Include models past their inference retirement date.")] = False,
    ) -> list[dict[str, Any]]:
        """List models that can be deployed on an account, with versions, SKUs and lifecycle."""
        acct = await client.account(account)
        models = await client.arm_list(f"{acct['id']}/models")
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        result = []
        for m in models:
            if name_contains and name_contains.lower() not in m.get("name", "").lower():
                continue
            retires = (m.get("deprecation") or {}).get("inference")
            if not include_deprecated and retires and retires < now:
                continue
            result.append({
                "name": m.get("name"),
                "version": m.get("version"),
                "format": m.get("format"),
                "default_version": m.get("isDefaultVersion", False),
                "lifecycle": m.get("lifecycleStatus"),
                "skus": sorted({s.get("name") for s in m.get("skus", []) if s.get("name")}),
                "inference_retires": retires,
                "marketplace_required": m.get("isMarketplaceRequired", False),
            })
        return sorted(result, key=lambda r: (r["name"] or "", r["version"] or ""))

    @mcp.tool(annotations=READ_ONLY)
    async def foundry_get_quota(
        account: AccountName,
        name_contains: Annotated[str | None, Field(description="Filter on quota name, e.g. a model name.")] = None,
    ) -> list[dict[str, Any]]:
        """Show model deployment quota (used / limit) in the account's region."""
        acct = await client.account(account)
        usages = await client.arm_list(
            f"/subscriptions/{client.subscription_id}/providers/Microsoft.CognitiveServices"
            f"/locations/{acct['location']}/usages"
        )
        result = []
        for u in usages:
            name = (u.get("name") or {}).get("value", "")
            if not u.get("limit") or (name_contains and _squash(name_contains) not in _squash(name)):
                continue
            result.append({"name": name, "used": u.get("currentValue"), "limit": u.get("limit"), "unit": u.get("unit")})
        return result

    @mcp.tool(annotations=READ_ONLY)
    async def foundry_list_deployments(account: AccountName) -> list[dict[str, Any]]:
        """List model deployments on a Foundry account."""
        acct = await client.account(account)
        deployments = await client.arm_list(f"{acct['id']}/deployments")
        return [{
            "name": d["name"],
            "model": (d.get("properties", {}).get("model") or {}).get("name"),
            "version": (d.get("properties", {}).get("model") or {}).get("version"),
            "format": (d.get("properties", {}).get("model") or {}).get("format"),
            "sku": (d.get("sku") or {}).get("name"),
            "capacity": (d.get("sku") or {}).get("capacity"),
            "state": d.get("properties", {}).get("provisioningState"),
        } for d in deployments]

    @mcp.tool(annotations=DESTRUCTIVE)
    async def foundry_deploy_model(
        account: AccountName,
        deployment_name: Annotated[str, Field(pattern=NAME_PATTERN, description="Deployment name; an existing deployment with this name is replaced.")],
        model: Annotated[str, Field(description="Catalog model name, e.g. gpt-4.1-mini (see foundry_list_models).")],
        version: Annotated[str | None, Field(description="Model version. Defaults to the catalog's default version.")] = None,
        sku: Annotated[str, Field(description="Deployment SKU, e.g. GlobalStandard, Standard, DataZoneStandard.")] = "GlobalStandard",
        capacity: Annotated[int, Field(ge=1, description="Capacity in thousands of tokens per minute for token-based SKUs.")] = 1,
    ) -> dict[str, Any]:
        """Create or update a model deployment and wait (up to 90 s) for it to finish provisioning."""
        acct = await client.account(account)
        catalog = [m for m in await client.arm_list(f"{acct['id']}/models") if m.get("name") == model]
        if version:
            catalog = [m for m in catalog if m.get("version") == version]
        else:
            catalog = sorted(catalog, key=lambda m: (bool(m.get("isDefaultVersion")), m.get("version", "")))[-1:]
        if not catalog:
            raise ToolError(f"Model '{model}'{f' version {version}' if version else ''} isn't deployable on '{account}'.")
        entry = catalog[0]
        if entry.get("isMarketplaceRequired"):
            raise ToolError(
                f"'{model}' requires an Azure Marketplace subscription, which bills outside Azure consumption; "
                "this connector only deploys consumption-billed models."
            )
        skus = {s.get("name") for s in entry.get("skus", [])}
        if sku not in skus:
            raise ToolError(f"SKU '{sku}' isn't offered for {model} {entry.get('version')}. Options: {sorted(skus)}")

        path = f"{acct['id']}/deployments/{deployment_name}"
        await client.arm("PUT", path, body={
            "sku": {"name": sku, "capacity": capacity},
            "properties": {
                "model": {"format": entry.get("format"), "name": model, "version": entry.get("version")},
                "versionUpgradeOption": "OnceNewDefaultVersionAvailable",
            },
        })
        deadline = time.monotonic() + DEPLOY_WAIT_SECONDS
        state = "Creating"
        while time.monotonic() < deadline:
            state = (await client.arm("GET", path)).get("properties", {}).get("provisioningState", "Unknown")
            if state in TERMINAL_STATES:
                break
            await asyncio.sleep(5)
        return {"deployment": deployment_name, "model": model, "version": entry.get("version"),
                "sku": sku, "capacity": capacity, "state": state}

    @mcp.tool(annotations=DESTRUCTIVE)
    async def foundry_delete_deployment(
        account: AccountName,
        deployment_name: Annotated[str, Field(pattern=NAME_PATTERN, description="Deployment to delete.")],
    ) -> dict[str, Any]:
        """Delete a model deployment. Agents that use it stop working."""
        acct = await client.account(account)
        await client.arm("DELETE", f"{acct['id']}/deployments/{deployment_name}")
        return {"deleted": deployment_name}

    @mcp.tool(annotations=READ_ONLY)
    async def foundry_list_agents(account: AccountName, project: ProjectName = None) -> list[dict[str, Any]]:
        """List agents in a Foundry project with their latest version and model."""
        listing = await client.project_call(account, project, "GET", "/agents")
        return [_summarize_agent(a) for a in listing.get("data", [])]

    @mcp.tool(annotations=READ_ONLY)
    async def foundry_get_agent(
        account: AccountName,
        name: Annotated[str, Field(pattern=NAME_PATTERN, description="Agent name.")],
        project: ProjectName = None,
    ) -> dict[str, Any]:
        """Get an agent's latest version, including its full definition (instructions, tools)."""
        agent = await client.project_call(account, project, "GET", f"/agents/{name}")
        latest = (agent.get("versions") or {}).get("latest") or {}
        return {**_summarize_agent(agent), "definition": latest.get("definition")}

    @mcp.tool(annotations=CREATES)
    async def foundry_create_or_update_agent(
        account: AccountName,
        name: Annotated[str, Field(pattern=NAME_PATTERN, description="Agent name. An existing agent gets a new version.")],
        model: Annotated[str, Field(description="Model DEPLOYMENT name on the account (see foundry_list_deployments).")],
        instructions: Annotated[str, Field(description="System instructions for the agent.")],
        description: Annotated[str | None, Field(description="Short description.")] = None,
        tools: Annotated[
            list[dict[str, Any]] | None,
            Field(description="Optional Foundry tool definitions, e.g. [{\"type\": \"web_search\"}]."),
        ] = None,
        project: ProjectName = None,
    ) -> dict[str, Any]:
        """Create a prompt agent, or publish a new version of an existing one."""
        definition: dict[str, Any] = {"kind": "prompt", "model": model, "instructions": instructions}
        if tools:
            definition["tools"] = tools
        body: dict[str, Any] = {"definition": definition, "metadata": {"created_via": "claude-azure-mcp"}}
        if description:
            body["description"] = description
        version = await client.project_call(account, project, "POST", f"/agents/{name}/versions", body=body)
        return {"name": version.get("name"), "version": version.get("version"), "status": version.get("status")}

    @mcp.tool(annotations=DESTRUCTIVE)
    async def foundry_delete_agent(
        account: AccountName,
        name: Annotated[str, Field(pattern=NAME_PATTERN, description="Agent to delete (all versions).")],
        project: ProjectName = None,
    ) -> dict[str, Any]:
        """Delete an agent and all of its versions."""
        result = await client.project_call(account, project, "DELETE", f"/agents/{name}")
        return {"deleted": result.get("name", name)}

    @mcp.tool(annotations=CREATES)
    async def foundry_run_agent(
        account: AccountName,
        name: Annotated[str, Field(pattern=NAME_PATTERN, description="Agent to run.")],
        input: Annotated[str, Field(description="User message to send to the agent.")],
        previous_response_id: Annotated[
            str | None, Field(description="Continue a conversation: the response_id from a previous run.")
        ] = None,
        project: ProjectName = None,
    ) -> dict[str, Any]:
        """Send a message to an agent and return its reply. Pass previous_response_id to continue a conversation."""
        body: dict[str, Any] = {"agent_reference": {"type": "agent_reference", "name": name}, "input": input}
        if previous_response_id:
            body["previous_response_id"] = previous_response_id
        response = await client.project_call(account, project, "POST", "/openai/v1/responses", body=body, versioned=False)
        return {
            "response_id": response.get("id"),
            "status": response.get("status"),
            "text": _response_text(response),
            "output_types": [item.get("type") for item in response.get("output", [])],
            "usage": response.get("usage"),
        }
