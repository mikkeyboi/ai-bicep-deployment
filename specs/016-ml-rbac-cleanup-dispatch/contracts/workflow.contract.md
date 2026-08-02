# Contract: guarded cleanup dispatch

## Workflow input

`migrate_legacy_ml_rbac` is a required boolean with default `false` and is honored
only for `workflow_dispatch`. `migration_confirmation` is an independently entered
string. Cleanup is rejected unless the environment is `dev` and both controls
match in the workflow and script.

## Cleanup script

The script requires the literal confirmation value
`delete-superseded-a100-h100-storage-grants`. It must:

- discover resources rather than embed IDs;
- emit only target names and deletion counts;
- require exactly one workspace, storage account, target compute per suffix, and
  eligible assignment per target;
- calculate the documented ARM `guid()` legacy and final IDs, delete only legacy
  IDs, retain final IDs, and reject unknown IDs;
- follow ARM collection pagination;
- validate every target before the first deletion;
- bind the deleted resource ID itself to the calculated legacy GUID and require
  distinct principals and assignment IDs;
- sanitize Azure CLI failures without printing command arguments or IDs.

The normal deployment step follows cleanup in the same authenticated job. Once a
valid cleanup request begins mutation, deployment must run even if one deletion
fails; a final guard preserves the cleanup failure after the convergence attempt.
