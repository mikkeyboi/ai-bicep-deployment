# Quickstart: guarded ML RBAC cleanup

Validate locally:

```bash
python3 -m py_compile scripts/cleanup_legacy_ml_rbac.py
python3 scripts/cleanup_legacy_ml_rbac.py --help
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy.yml'))"
```

After merge, run exactly once:

```bash
gh workflow run deploy.yml \
  -f environment=dev \
  -f migrate_legacy_ml_rbac=true
```

Watch the dispatched run to terminal success, verify final narrow grants, then
remove obsolete broad grants and legacy V100/T4 compute.
