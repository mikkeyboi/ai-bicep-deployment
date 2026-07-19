# Contract: guarded cleanup dispatch

## Workflow input

`migrate_legacy_ml_rbac` is a required boolean with default `false` and is honored
only for `workflow_dispatch`.

## Cleanup script

The script requires the literal confirmation value
`delete-superseded-a100-h100-storage-grants`. It must:

- discover resources rather than embed IDs;
- emit only target names and deletion counts;
- require exactly one workspace, storage account, target compute per suffix, and
  eligible assignment per target;
- stop on the first mismatch or Azure error.

The normal deployment step follows cleanup in the same authenticated job.
