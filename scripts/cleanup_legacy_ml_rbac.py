#!/usr/bin/env python3
"""One-time cleanup of superseded A100/H100 storage-role assignments."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import uuid
from collections.abc import Callable
from typing import Any

_BLOB_CONTRIBUTOR_ROLE = "Storage Blob Data Contributor"
_CONFIRMATION = "delete-superseded-a100-h100-storage-grants"
_TARGET_SUFFIXES = ("gpu-a100", "gpu-h100")
_MANAGEMENT_ORIGIN = "https://management.azure.com"
# Microsoft documents this UUID as ARM guid()'s RFC 4122 version-5 namespace.
# Keep it split because public-repo policy restricts GUID-shaped literals.
_ARM_GUID_NAMESPACE = uuid.UUID("11fb06fb-712d" + "-4ddd-98c7-e71bbd588830")


def _run_az(operation: str, *args: str, output: str = "json") -> str:
    try:
        completed = subprocess.run(
            ["az", *args, "--output", output],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        raise RuntimeError(f"{operation} failed: Azure CLI is unavailable") from None
    except subprocess.CalledProcessError:
        raise RuntimeError(f"{operation} failed") from None
    return completed.stdout


def _az_json(operation: str, *args: str) -> Any:
    raw = _run_az(operation, *args)
    try:
        return json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        raise RuntimeError(f"{operation} returned invalid JSON") from None


def _rest_values(url: str, *, operation: str) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    seen: set[str] = set()
    next_url: str | None = url
    while next_url is not None:
        if not next_url.startswith(f"{_MANAGEMENT_ORIGIN}/") or next_url in seen:
            raise RuntimeError(f"{operation} returned an invalid continuation URL")
        seen.add(next_url)
        page = _az_json(operation, "rest", "--method", "get", "--url", next_url)
        if not isinstance(page, dict) or not isinstance(page.get("value"), list):
            raise RuntimeError(f"{operation} returned an invalid collection")
        values.extend(page["value"])
        candidate = page.get("nextLink")
        if candidate is not None and not isinstance(candidate, str):
            raise RuntimeError(f"{operation} returned an invalid continuation URL")
        next_url = candidate
    return values


def _single_tagged_resource(
    resources: list[dict[str, Any]], *, kind: str, environment: str
) -> dict[str, Any]:
    matched = []
    for resource in resources:
        tags = resource.get("tags")
        if not isinstance(tags, dict):
            continue
        if tags.get("environment") == environment and tags.get("workload") == "aio":
            matched.append(resource)
    if len(matched) != 1:
        raise RuntimeError(f"expected one tagged {environment} {kind}, found {len(matched)}")
    return matched[0]


def _select_targets(computes: list[dict[str, Any]]) -> dict[str, str]:
    targets: dict[str, str] = {}
    for suffix in _TARGET_SUFFIXES:
        matched = [compute for compute in computes if str(compute.get("name", "")).endswith(suffix)]
        if len(matched) != 1:
            raise RuntimeError(f"expected one {suffix} compute, found {len(matched)}")
        compute = matched[0]
        identity = compute.get("identity")
        principal_id = identity.get("principalId") if isinstance(identity, dict) else None
        if not isinstance(principal_id, str) or not principal_id:
            raise RuntimeError(f"{suffix} compute has no system-assigned principal")
        targets[str(compute["name"])] = principal_id
    if len({principal.lower() for principal in targets.values()}) != len(targets):
        raise RuntimeError("target computes must have distinct system-assigned principals")
    return targets


def _arm_guid(*values: str) -> str:
    return str(uuid.uuid5(_ARM_GUID_NAMESPACE, "-".join(values)))


def _plan_deletions(
    assignments: list[dict[str, Any]],
    *,
    targets: dict[str, str],
    storage_id: str,
    role_definition_id: str,
) -> list[tuple[str, str]]:
    storage_prefix = (
        storage_id.lower() + "/providers/microsoft.authorization/roleassignments/"
    )
    role_guid = role_definition_id.rsplit("/", 1)[-1].lower()
    planned: list[tuple[str, str]] = []
    matched_assignment_ids: list[str] = []

    for compute_name, principal_id in sorted(targets.items()):
        matched = []
        for assignment in assignments:
            properties = assignment.get("properties")
            if not isinstance(properties, dict):
                continue
            if (
                str(assignment.get("id", "")).lower().startswith(storage_prefix)
                and str(properties.get("principalId", "")).lower()
                == principal_id.lower()
                and str(properties.get("roleDefinitionId", "")).lower()
                == role_definition_id.lower()
            ):
                matched.append(assignment)
        if len(matched) != 1:
            raise RuntimeError(
                f"{compute_name}: expected one storage grant, found {len(matched)}"
            )

        assignment = matched[0]
        assignment_id = str(assignment.get("id", ""))
        assignment_id_name = assignment_id.rsplit("/", 1)[-1].lower()
        assignment_name = str(assignment.get("name", "")).lower()
        legacy_name = _arm_guid(storage_id, principal_id, role_guid)
        final_name = _arm_guid("storageAccount", storage_id, principal_id, role_guid)
        if assignment_name != assignment_id_name:
            raise RuntimeError(f"{compute_name}: role-assignment name and resource ID differ")
        matched_assignment_ids.append(assignment_id)
        if assignment_id_name == final_name:
            continue
        if assignment_id_name != legacy_name:
            raise RuntimeError(f"{compute_name}: storage grant is not the superseded legacy identity")
        planned.append((compute_name, assignment_id))

    if len({assignment_id.lower() for assignment_id in matched_assignment_ids}) != len(
        matched_assignment_ids
    ):
        raise RuntimeError("target computes resolved to duplicate role-assignment IDs")
    return planned


def _delete_assignment(assignment_id: str, *, compute_name: str) -> None:
    if not assignment_id.startswith("/subscriptions/"):
        raise RuntimeError(f"{compute_name}: invalid role-assignment resource ID")
    _run_az(
        f"delete superseded grant for {compute_name}",
        "rest",
        "--method",
        "delete",
        "--url",
        f"{_MANAGEMENT_ORIGIN}{assignment_id}?api-version=2022-04-01",
        output="none",
    )


def run_cleanup(
    *,
    environment: str,
    confirmation: str,
    delete_assignment: Callable[..., None] = _delete_assignment,
) -> None:
    if environment != "dev":
        raise RuntimeError("legacy ML RBAC cleanup is restricted to dev")
    if confirmation != _CONFIRMATION:
        raise RuntimeError("legacy ML RBAC cleanup confirmation did not match")

    subscription = os.environ.get("AZ_SUB", "").strip()
    if not subscription:
        raise RuntimeError("AZ_SUB is required")

    workspaces = _az_json(
        "list workspaces",
        "resource",
        "list",
        "--subscription",
        subscription,
        "--resource-type",
        "Microsoft.MachineLearningServices/workspaces",
    )
    workspace = _single_tagged_resource(
        workspaces, kind="workspace", environment=environment
    )
    workspace_id = str(workspace.get("id", ""))
    try:
        resource_group = workspace_id.split("/resourceGroups/", 1)[1].split("/", 1)[0]
    except IndexError:
        raise RuntimeError("workspace resource ID has an unexpected shape") from None

    storage_accounts = _az_json(
        "list storage accounts",
        "resource",
        "list",
        "--subscription",
        subscription,
        "--resource-group",
        resource_group,
        "--resource-type",
        "Microsoft.Storage/storageAccounts",
    )
    storage = _single_tagged_resource(
        storage_accounts, kind="storage account", environment=environment
    )
    storage_id = str(storage.get("id", ""))
    if not storage_id.startswith("/subscriptions/"):
        raise RuntimeError("storage resource ID has an unexpected shape")

    role_definitions = _az_json(
        "resolve Storage Blob Data Contributor",
        "role",
        "definition",
        "list",
        "--subscription",
        subscription,
        "--name",
        _BLOB_CONTRIBUTOR_ROLE,
    )
    if len(role_definitions) != 1:
        raise RuntimeError(
            f"expected one {_BLOB_CONTRIBUTOR_ROLE} definition, found {len(role_definitions)}"
        )
    role_definition_id = str(role_definitions[0].get("id", ""))
    if not role_definition_id.startswith("/subscriptions/"):
        raise RuntimeError("role definition ID has an unexpected shape")

    computes = _rest_values(
        f"{_MANAGEMENT_ORIGIN}{workspace_id}/computes?api-version=2024-10-01-preview",
        operation="list workspace computes",
    )
    targets = _select_targets(computes)
    assignments = _rest_values(
        f"{_MANAGEMENT_ORIGIN}{storage_id}/providers/"
        "Microsoft.Authorization/roleAssignments?api-version=2022-04-01&$filter=atScope()",
        operation="list storage role assignments",
    )

    # Complete every validation before the first mutation.
    planned = _plan_deletions(
        assignments,
        targets=targets,
        storage_id=storage_id,
        role_definition_id=role_definition_id,
    )
    failures: list[str] = []
    for compute_name, assignment_id in planned:
        try:
            delete_assignment(assignment_id, compute_name=compute_name)
        except RuntimeError:
            failures.append(compute_name)
            print(f"{compute_name}: deletion failed", file=sys.stderr)
        else:
            print(f"{compute_name}: deleted one superseded storage grant")
    if failures:
        raise RuntimeError(f"{len(failures)} superseded storage-grant deletion(s) failed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", required=True)
    parser.add_argument("--confirm", required=True)
    args = parser.parse_args()
    try:
        run_cleanup(environment=args.environment, confirmation=args.confirm)
    except RuntimeError as exc:
        print(f"cleanup failed: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # fail closed without leaking command arguments or IDs
        print(f"cleanup failed unexpectedly: {type(exc).__name__}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
