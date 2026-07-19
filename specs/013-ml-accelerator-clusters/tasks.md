# Tasks: low-priority accelerator clusters

- [x] Confirm A100 and H100 appear as low-priority-capable Azure ML sizes.
- [x] Confirm AzureML's regional low-priority cluster quota is 200 vCPUs.
- [x] Specify A100/H100 as the only desired GPU strata.
- [x] Add optional cluster naming suffix to the shared type.
- [x] Resolve distinct names through the central naming helper.
- [x] Add A100 and H100 dev cluster entries; remove V100/T4 desired entries.
- [x] Compile main and dev/test/prod parameters.
- [x] Verify compiled names, SKUs, priority, scale, identity, and RBAC wiring.
- [x] Run secret/privacy scans and `git diff --check`.
- [x] Open a public PR and review CI validate/what-if output.
- [ ] Provision scale-to-zero A100/H100 cluster definitions.
- [ ] Verify both definitions, then explicitly delete legacy V100/T4 clusters.
- [ ] Run one-node allocation smokes and record success or capacity failures.
