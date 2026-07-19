#!/usr/bin/env python3
"""One-time cleanup of superseded A100/H100 storage-role assignments."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from typing import Any

_BLOB_CONTRIBUTOR_ROLE = "Storage Blob Data Contributor"
_TARGET_SUFFIXES = ("gpu-a100", "gpu-h100")


def _az_json(*args: str) -> Any:
    completed = subprocess.run(
        ["az", *args, "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def _single_tagged_resource(resources: list[dict[str, Any]], *, kind: str) -> dict[str, Any]:
    matched = [
        resource
        for resource in resources
        if resource.get("tags", {}).get("environment") == "dev"
        and resource.get("tags", {}).get("workload") == "aio"
    ]
    if len(matched) != 1:
        raise RuntimeError(f"expected one tagged dev {kind}, found {len(matched)}")
    return matched[0]


def _delete(url: str) -> None:
    subprocess.run(
        ["az", "rest", "--method", "delete", "--url", url, "--output", "none"],
        check=True,
        capture_output=True,
        text=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--confirm",
        required=True,
        choices=["delete-superseded-a100-h100-storage-grants"],
    )
    args = parser.parse_args()
    del args

    subscription = os.environ.get("AZ_SUB", "").strip()
    if not subscription:
        raise RuntimeError("AZ_SUB is required")

    workspaces = _az_json(
        "resource",
        "list",
        "--subscription",
        subscription,
        "--resource-type",
        "Microsoft.MachineLearningServices/workspaces",
    )
    workspace = _single_tagged_resource(workspaces, kind="workspace")
    resource_group = workspace["id"].split("/resourceGroups/", 1)[1].split("/", 1)[0]

    storage_accounts = _az_json(
        "resource",
        "list",
        "--subscription",
        subscription,
        "--resource-group",
        resource_group,
        "--resource-type",
        "Microsoft.Storage/storageAccounts",
    )
    storage = _single_tagged_resource(storage_accounts, kind="storage account")
    role_definitions = _az_json(
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
    role_definition_id = role_definitions[0]["id"].lower()

    computes_url = (
        f"https://management.azure.com{workspace['id']}/computes"
        "?api-version=2024-10-01-preview"
    )
    computes = _az_json("rest", "--method", "get", "--url", computes_url)["value"]
    targets = {
        compute["name"]: compute["identity"]["principalId"]
        for compute in computes
        if any(compute["name"].endswith(suffix) for suffix in _TARGET_SUFFIXES)
    }
    if len(targets) != len(_TARGET_SUFFIXES):
        raise RuntimeError(f"expected {len(_TARGET_SUFFIXES)} target computes, found {len(targets)}")

    assignments_url = (
        f"https://management.azure.com{storage['id']}"
        "/providers/Microsoft.Authorization/roleAssignments"
        "?api-version=2022-04-01&$filter=atScope()"
    )
    assignments = _az_json("rest", "--method", "get", "--url", assignments_url)["value"]
    storage_prefix = storage["id"].lower() + "/providers/microsoft.authorization/roleassignments/"

    for compute_name, principal_id in sorted(targets.items()):
        matched = [
            assignment
            for assignment in assignments
            if assignment["id"].lower().startswith(storage_prefix)
            and assignment["properties"].get("principalId", "").lower()
            == principal_id.lower()
            and assignment["properties"].get("roleDefinitionId", "").lower()
            == role_definition_id
        ]
        if len(matched) != 1:
            raise RuntimeError(
                f"{compute_name}: expected one superseded storage grant, found {len(matched)}"
            )
        _delete(
            f"https://management.azure.com{matched[0]['id']}?api-version=2022-04-01"
        )
        print(f"{compute_name}: deleted one superseded storage grant")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
