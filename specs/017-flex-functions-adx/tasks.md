# Tasks — 017

- [x] T1 Naming: `functionApp`, `functionPlan`, `adxCluster`
- [x] T2 Types: `functionAppConfig`, `dataExplorerConfig`, optional on `environmentConfig`
- [x] T3 `modules/function-app/main.bicep` (Flex, keyless deployment mount)
- [x] T4 `modules/data-explorer/main.bicep` (cluster + database)
- [x] T5 Wire both into `workload.bicep` behind default-off flags
- [x] T6 Back-fill function-identity RBAC (storage, Foundry, Search)
- [x] T7 Outputs incl. `functionAppPrincipalId` for the ingestor grant
- [x] T8 `main.dev.bicepparam` blocks; test/prod untouched
- [x] T9 `bicep build` + `build-params` clean for dev/test/prod
- [x] T10 Verify compiled ARM: FC1/FlexConsumption, Kusto, no new `listKeys`
- [ ] T11 Deploy to dev via CI and confirm the Flex app runs the timer
- [ ] T12 Re-verify ADX rows arrive from the Flex app's identity
- [ ] T13 Delete the superseded Y1 app + `EastUS2LinuxDynamicPlan`
- [ ] T14 Confirm `az deployment sub what-if` reports no unexpected deletes

## Open

1. **ADX cluster is currently un-imported.** The live cluster was portal-created and the
   template will create a *differently named* one (`dec...` vs `adxaiodevhvac`) rather
   than adopting it. Either import the existing cluster into the template's name, or
   accept a migration of the `hvac` data. Until that is decided, `dataExplorer.enabled`
   in dev deploys a second cluster — **T11 must confirm this is intended before merge.**
2. Function app deployment slots / staging are not modelled. Not needed for a timer, but
   worth revisiting if an HTTP surface is added.
