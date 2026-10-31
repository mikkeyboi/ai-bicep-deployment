"""Image generation tools served by the gateway (feature 016).

Generates images with Foundry image deployments (OpenAI gpt-image-* on the
OpenAI v1 route, Microsoft MAI-Image-* on the MAI route) as the Azure MCP
Server identity. Each image comes back two ways:

- a JPEG preview (max 1024 px) inline in the tool result, so the model and
  the user can see it;
- the full-resolution original in the `generated-images` blob container,
  behind a read-only user-delegation SAS link that expires. The identity can
  write to that one container only, and a user-delegation SAS can never grant
  more than the identity's own RBAC.
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any, Literal

from azure.identity.aio import ManagedIdentityCredential
from azure.storage.blob import BlobSasPermissions, ContentSettings, generate_blob_sas
from azure.storage.blob.aio import BlobServiceClient
from mcp.types import TextContent
from PIL import Image as PILImage
from pydantic import Field

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from fastmcp.tools import ToolResult
from fastmcp.utilities.types import Image

from foundry_tools import CREATES, NAME_PATTERN, READ_ONLY, AccountName, FoundryClient

IMAGE_TIMEOUT_SECONDS = 240.0
PREVIEW_MAX_SIDE = 1024
PREVIEW_JPEG_QUALITY = 85
MAI_MIN_SIDE = 768
MAI_MAX_PIXELS = 1_048_576
MIME_TYPES = {"png": "image/png", "jpeg": "image/jpeg", "webp": "image/webp"}


class ImageStore:
    """Full-resolution originals in one blob container, shared via short-lived SAS links."""

    def __init__(self, credential: ManagedIdentityCredential, account_url: str, container: str) -> None:
        self._service = BlobServiceClient(account_url, credential=credential)
        self._container = container

    async def save(self, data: bytes, name: str, image_format: str, expiry: datetime) -> str:
        blob = self._service.get_blob_client(self._container, name)
        await blob.upload_blob(
            data, overwrite=False, content_settings=ContentSettings(content_type=MIME_TYPES[image_format])
        )
        start = datetime.now(timezone.utc) - timedelta(minutes=5)
        key = await self._service.get_user_delegation_key(start, expiry)
        sas = generate_blob_sas(
            account_name=self._service.account_name,
            container_name=self._container,
            blob_name=name,
            user_delegation_key=key,
            permission=BlobSasPermissions(read=True),
            start=start,
            expiry=expiry,
        )
        return f"{blob.url}?{sas}"


def _preview_jpeg(data: bytes) -> bytes:
    with PILImage.open(io.BytesIO(data)) as image:
        image = image.convert("RGB")
        image.thumbnail((PREVIEW_MAX_SIDE, PREVIEW_MAX_SIDE))
        out = io.BytesIO()
        image.save(out, format="JPEG", quality=PREVIEW_JPEG_QUALITY, optimize=True)
        return out.getvalue()


def _image_api(deployment: dict[str, Any]) -> str:
    return "openai" if (deployment.get("properties", {}).get("model") or {}).get("format") == "OpenAI" else "mai"


def _parse_size(size: str) -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)x(\d+)", size)
    if not match:
        raise ToolError(f"size must look like WIDTHxHEIGHT, got '{size}'")
    return int(match[1]), int(match[2])


def register_image_tools(mcp: FastMCP, client: FoundryClient, store: ImageStore) -> None:
    @mcp.tool(annotations=READ_ONLY)
    async def foundry_list_image_deployments() -> list[dict[str, Any]]:
        """List image-generation deployments across all Foundry accounts, with the sizes each accepts."""
        result = []
        for account in (await client.accounts(refresh=True)).values():
            for d in await client.arm_list(f"{account['id']}/deployments"):
                caps = d.get("properties", {}).get("capabilities") or {}
                if caps.get("imageGenerations") != "true":
                    continue
                model = d.get("properties", {}).get("model") or {}
                api = _image_api(d)
                result.append({
                    "account": account["name"],
                    "deployment": d["name"],
                    "model": model.get("name"),
                    "version": model.get("version"),
                    "state": d.get("properties", {}).get("provisioningState"),
                    "supports_edits": caps.get("imageEdits") == "true",
                    "sizes": "1024x1024, 1536x1024, 1024x1536 or auto" if api == "openai"
                    else f"any WIDTHxHEIGHT with both sides >= {MAI_MIN_SIDE} and at most {MAI_MAX_PIXELS:,} pixels",
                    "quality_options": ["auto", "low", "medium", "high"] if api == "openai" else [],
                })
        return result

    @mcp.tool(annotations=CREATES)
    async def foundry_generate_image(
        account: AccountName,
        deployment: Annotated[str, Field(pattern=NAME_PATTERN, description="Image deployment (see foundry_list_image_deployments).")],
        prompt: Annotated[str, Field(min_length=1, max_length=32000, description="What to draw.")],
        size: Annotated[str, Field(description="WIDTHxHEIGHT, e.g. 1024x1024 (gpt-image also accepts 'auto').")] = "1024x1024",
        quality: Annotated[
            Literal["auto", "low", "medium", "high"], Field(description="gpt-image only; ignored for MAI models.")
        ] = "auto",
        count: Annotated[int, Field(ge=1, le=4, description="Number of images.")] = 1,
        output_format: Annotated[
            Literal["png", "jpeg", "webp"], Field(description="Full-resolution format (gpt-image only; MAI returns PNG).")
        ] = "png",
        link_hours: Annotated[int, Field(ge=1, le=168, description="Hours until the download links expire.")] = 24,
    ) -> ToolResult:
        """Generate images with a Foundry image deployment. Returns inline previews plus expiring links to the full-resolution files."""
        acct = await client.account(account)
        dep = await client.arm("GET", f"{acct['id']}/deployments/{deployment}")
        if (dep.get("properties", {}).get("capabilities") or {}).get("imageGenerations") != "true":
            raise ToolError(f"'{deployment}' isn't an image-generation deployment; see foundry_list_image_deployments.")
        api = _image_api(dep)

        if api == "openai":
            if size != "auto":
                _parse_size(size)
            result = await client.inference(account, "/openai/v1/images/generations", {
                "model": deployment, "prompt": prompt, "size": size, "quality": quality,
                "n": count, "output_format": output_format,
            }, timeout=IMAGE_TIMEOUT_SECONDS)
            images = [(base64.b64decode(item["b64_json"]), output_format) for item in result.get("data", [])]
            usage = result.get("usage")
        else:
            width, height = _parse_size(size)
            if min(width, height) < MAI_MIN_SIDE or width * height > MAI_MAX_PIXELS:
                raise ToolError(
                    f"MAI image sizes need both sides >= {MAI_MIN_SIDE} and at most {MAI_MAX_PIXELS:,} pixels; got {size}."
                )
            body = {"model": deployment, "prompt": prompt, "width": width, "height": height}
            results = await asyncio.gather(*(
                client.inference(account, "/mai/v1/images/generations", body, timeout=IMAGE_TIMEOUT_SECONDS)
                for _ in range(count)
            ))
            images = [(base64.b64decode(item["b64_json"]), "png") for r in results for item in r.get("data", [])]
            usage = [r.get("usage") for r in results]
        if not images:
            raise ToolError("The deployment returned no images (the prompt may have been filtered).")

        expiry = datetime.now(timezone.utc) + timedelta(hours=link_hours)
        stamp = datetime.now(timezone.utc).strftime("%Y/%m/%d/%H%M%S")
        batch = uuid.uuid4().hex[:8]
        entries, previews = [], []
        for index, (data, image_format) in enumerate(images, start=1):
            ext = "jpg" if image_format == "jpeg" else image_format
            name = f"{stamp}-{deployment}-{batch}-{index}.{ext}"
            url, preview = await asyncio.gather(
                store.save(data, name, image_format, expiry), asyncio.to_thread(_preview_jpeg, data)
            )
            entries.append({"download_url": url, "blob": name, "format": image_format, "bytes": len(data)})
            previews.append(Image(data=preview, format="jpeg").to_image_content())

        summary = {
            "account": account,
            "deployment": deployment,
            "size": size,
            "images": entries,
            "links_expire": expiry.isoformat(timespec="seconds"),
            "usage": usage,
        }
        return ToolResult(
            content=[TextContent(type="text", text=json.dumps(summary)), *previews],
            structured_content=summary,
        )
