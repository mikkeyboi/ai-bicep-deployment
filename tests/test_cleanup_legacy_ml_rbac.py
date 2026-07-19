from __future__ import annotations

import subprocess
import unittest
from unittest.mock import Mock, patch

from scripts import cleanup_legacy_ml_rbac as cleanup


_SUBSCRIPTION = "sub"
_WORKSPACE_ID = (
    "/subscriptions/sub/resourceGroups/rg-dev/providers/"
    "Microsoft.MachineLearningServices/workspaces/mlw-dev"
)
_STORAGE_ID = (
    "/subscriptions/sub/resourceGroups/rg-dev/providers/"
    "Microsoft.Storage/storageAccounts/storage-dev"
)
_ROLE_ID = (
    "/subscriptions/sub/providers/Microsoft.Authorization/roleDefinitions/role-id"
)


def _compute(name: str, principal: str) -> dict:
    return {"name": name, "identity": {"principalId": principal}}


def _assignment(name: str, principal: str) -> dict:
    return {
        "name": name,
        "id": (
            f"{_STORAGE_ID}/providers/Microsoft.Authorization/roleAssignments/{name}"
        ),
        "properties": {
            "principalId": principal,
            "roleDefinitionId": _ROLE_ID,
        },
    }


def _legacy_assignment(principal: str) -> dict:
    role = _ROLE_ID.rsplit("/", 1)[-1]
    return _assignment(cleanup._arm_guid(_STORAGE_ID, principal, role), principal)


def _final_assignment(principal: str) -> dict:
    role = _ROLE_ID.rsplit("/", 1)[-1]
    return _assignment(
        cleanup._arm_guid("storageAccount", _STORAGE_ID, principal, role),
        principal,
    )


class CleanupSelectionTests(unittest.TestCase):
    def test_null_tags_are_ignored_by_cardinality_check(self):
        resources = [
            {"tags": None},
            {"tags": {"environment": "dev", "workload": "aio"}},
        ]

        selected = cleanup._single_tagged_resource(
            resources, kind="workspace", environment="dev"
        )

        self.assertEqual(selected["tags"]["workload"], "aio")

    def test_null_compute_identity_fails_with_clear_error(self):
        computes = [
            {"name": "cc-dev-gpu-a100", "identity": None},
            _compute("cc-dev-gpu-h100", "principal-h"),
        ]

        with self.assertRaisesRegex(RuntimeError, "has no system-assigned principal"):
            cleanup._select_targets(computes)

    def test_requires_exactly_one_compute_per_suffix(self):
        computes = [
            _compute("cc-dev-gpu-a100", "principal-a"),
            _compute("cc-dev-gpu-a100", "principal-b"),
        ]

        with self.assertRaisesRegex(RuntimeError, "expected one gpu-a100"):
            cleanup._select_targets(computes)

    def test_rejects_final_assignment_on_rerun(self):
        targets = {
            "cc-dev-gpu-a100": "principal-a",
            "cc-dev-gpu-h100": "principal-h",
        }
        assignments = [
            _final_assignment("principal-a"),
            _legacy_assignment("principal-h"),
        ]

        with self.assertRaisesRegex(RuntimeError, "final storage grant already exists"):
            cleanup._plan_deletions(
                assignments,
                targets=targets,
                storage_id=_STORAGE_ID,
                role_definition_id=_ROLE_ID,
            )

    def test_rejects_unknown_assignment_identity(self):
        targets = {
            "cc-dev-gpu-a100": "principal-a",
            "cc-dev-gpu-h100": "principal-h",
        }
        assignments = [
            _assignment("unexpected", "principal-a"),
            _legacy_assignment("principal-h"),
        ]

        with self.assertRaisesRegex(RuntimeError, "not the superseded legacy identity"):
            cleanup._plan_deletions(
                assignments,
                targets=targets,
                storage_id=_STORAGE_ID,
                role_definition_id=_ROLE_ID,
            )


class CleanupExecutionTests(unittest.TestCase):
    def _az_json(self, operation: str, *args: str):
        del args
        if operation == "list workspaces":
            return [
                {
                    "id": _WORKSPACE_ID,
                    "tags": {"environment": "dev", "workload": "aio"},
                }
            ]
        if operation == "list storage accounts":
            return [
                {
                    "id": _STORAGE_ID,
                    "tags": {"environment": "dev", "workload": "aio"},
                }
            ]
        if operation == "resolve Storage Blob Data Contributor":
            return [{"id": _ROLE_ID}]
        raise AssertionError(operation)

    @patch.dict("os.environ", {"AZ_SUB": _SUBSCRIPTION}, clear=True)
    @patch.object(cleanup, "_az_json")
    @patch.object(cleanup, "_rest_values")
    def test_validates_both_targets_before_any_delete(self, rest_values, az_json):
        az_json.side_effect = self._az_json
        rest_values.side_effect = [
            [
                _compute("cc-dev-gpu-a100", "principal-a"),
                _compute("cc-dev-gpu-h100", "principal-h"),
            ],
            [
                _legacy_assignment("principal-a"),
                _assignment("unexpected", "principal-h"),
            ],
        ]
        delete = Mock()

        with self.assertRaisesRegex(RuntimeError, "not the superseded legacy identity"):
            cleanup.run_cleanup(
                environment="dev",
                confirmation=cleanup._CONFIRMATION,
                delete_assignment=delete,
            )

        delete.assert_not_called()

    @patch.dict("os.environ", {"AZ_SUB": _SUBSCRIPTION}, clear=True)
    @patch.object(cleanup, "_az_json")
    @patch.object(cleanup, "_rest_values")
    def test_deletes_exactly_two_prevalidated_legacy_assignments(
        self, rest_values, az_json
    ):
        az_json.side_effect = self._az_json
        rest_values.side_effect = [
            [
                _compute("cc-dev-gpu-a100", "principal-a"),
                _compute("cc-dev-gpu-h100", "principal-h"),
            ],
            [
                _legacy_assignment("principal-a"),
                _legacy_assignment("principal-h"),
            ],
        ]
        delete = Mock()

        cleanup.run_cleanup(
            environment="dev",
            confirmation=cleanup._CONFIRMATION,
            delete_assignment=delete,
        )

        self.assertEqual(delete.call_count, 2)

    def test_rejects_non_dev_before_discovery(self):
        with self.assertRaisesRegex(RuntimeError, "restricted to dev"):
            cleanup.run_cleanup(
                environment="prod",
                confirmation=cleanup._CONFIRMATION,
            )

    def test_requires_operator_confirmation(self):
        with self.assertRaisesRegex(RuntimeError, "confirmation did not match"):
            cleanup.run_cleanup(environment="dev", confirmation="wrong")


class CleanupTransportTests(unittest.TestCase):
    @patch.object(cleanup, "_az_json")
    def test_rest_collection_follows_pagination(self, az_json):
        second = f"{cleanup._MANAGEMENT_ORIGIN}/next"
        az_json.side_effect = [
            {"value": [{"name": "first"}], "nextLink": second},
            {"value": [{"name": "second"}]},
        ]

        values = cleanup._rest_values(
            f"{cleanup._MANAGEMENT_ORIGIN}/first", operation="list resources"
        )

        self.assertEqual([item["name"] for item in values], ["first", "second"])
        self.assertEqual(az_json.call_count, 2)

    @patch.object(subprocess, "run")
    def test_cli_failure_does_not_disclose_command_arguments(self, run):
        run.side_effect = subprocess.CalledProcessError(
            1, ["az", "rest", "--url", "https://example.invalid/sensitive-id"]
        )

        with self.assertRaisesRegex(RuntimeError, "delete grant failed") as raised:
            cleanup._run_az(
                "delete grant",
                "rest",
                "--url",
                "https://example.invalid/sensitive-id",
            )

        self.assertNotIn("sensitive-id", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
