# Tasks: low-priority accelerator clusters

- [x] Confirm A100 and H100 appear as low-priority-capable Azure ML sizes.
- [x] Record regional low-priority quota and per-node vCPU requirements.
- [x] Specify T4 backfill and A100/H100 hardware-replication strata.
- [x] Add optional cluster naming suffix to the shared type.
- [x] Resolve distinct names through the central naming helper.
- [x] Add T4, A100, and H100 dev cluster entries.
- [x] Compile main and dev/test/prod parameters.
- [x] Verify compiled names, SKUs, priority, scale, identity, and RBAC wiring.
- [x] Run secret/privacy scans and `git diff --check`.
- [ ] Open a public PR and review CI validate/what-if output.
- [ ] Provision scale-to-zero cluster definitions.
- [ ] Run one-node allocation smokes and record success or quota/capacity failures.
