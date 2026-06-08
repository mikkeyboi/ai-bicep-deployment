# Feature 009: ML cluster-only for dev-green (defer the compute instance)

**Branch**: `009-ml-cluster-only-dev-green` | **Constitution**: v1.2.0
**Follows**: 007 (added ML), 008 (fixed compute ordering).

## Problem

After 008 fixed the compute **ordering** (role assignments now provably
created before compute), the dev deploy STILL failed — three consecutive
times — on the compute **instance** with:

```
StorageMountError: ci-aio-dev-eus2-cpu ... Miss required permission
Storage File Data Privileged Contributor ... assign to <workspace-MSI>.
```

`az deployment group list` proved the ordering held every time:

```
ml-ws       Succeeded  21:54:26
ra-ml-file  Succeeded  21:54:37   <- file role created
ra-ml-blob  Succeeded  21:54:38
ra-ml-kv    Succeeded  21:54:39
ml-compute  Failed     21:59:06   <- 4.5 min LATER, still "miss permission"
```

So the cause is **not** control-plane ordering. It is RBAC **data-plane
propagation lag** to the storage file/SMB endpoint (and possibly a
missing file-datastore permission). Microsoft's own Q&A threads confirm
this class of failure persists even with the documented role set, and
that "if you recently updated the role, try after sometime." ARM's
natural ~3.5 min gap is below the propagation window.

## Decision

**Ship the workspace + compute CLUSTER now; DEFER the compute INSTANCE.**

- The cluster (`minNodeCount: 0`) does **not** mount `workspacefilestore`
  at create, so it deploys cleanly and gives dev a working, autoscaling
  ML compute target immediately.
- The instance is the only resource that mounts filestore at create, so
  it is the only thing blocked by the propagation issue. It is deferred
  (set `computeInstances: []`, with a documented re-add stub) rather than
  blocking all of ML on it.

This unblocks dev with zero added infra complexity (no deploymentScript
sleep, no UAI re-architecture) and isolates the instance-mount RBAC
question as a tracked follow-up.

## Change

`infra/parameters/main.dev.bicepparam` only: `machineLearning.computeInstances`
→ `[]` (entry preserved as a comment). No module/type/workload changes —
the 008 split modules and ordering stay exactly as merged.

## Acceptance

- `bicep build` + `build-params(dev/test/prod)` clean.
- Dev deploy succeeds: `mlw-aio-dev-eus2` + `cc-aio-dev-eus2-cpu` (cluster,
  0 nodes idle). No compute instance.

## Open follow-up (separate feature)

Restore the compute instance once the file-datastore mount is solved.
Investigate, with a working `az login` (Graph token) to inspect live RBAC
(`az role assignment list --scope <storage-id> --include-inherited`):

1. **Confirm the exact role set.** Try adding **Storage File Data SMB
   Share Contributor** and/or **Storage Account Contributor** to the
   workspace MSI — Microsoft threads show the blob+file-priv pair alone is
   sometimes insufficient for the SMB mount.
2. **Or add a propagation wait** — a `Microsoft.Resources/deploymentScripts`
   that sleeps ~5 min between the grants and the instance (downside: needs
   its own storage + ACI).
3. Whichever is chosen, prove it with ONE live deploy of the instance
   before re-enabling it in the paramfile. Don't stack remedies blindly.

## Constitution Check (v1.2.0)

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Paramfile-only; empty list is valid + idempotent. |
| IV. Modular / Single Entry | PASS | No module changes; literals stay in the paramfile. |
| VI. Validation Gates | PASS | build + build-params(×3) clean; validate/what-if/gitleaks in CI. |
| VII. Environment Parity | PASS | `machineLearning` still optional; test/prod unaffected. |

No Complexity Tracking entries (a scope reduction, not a posture deviation).
