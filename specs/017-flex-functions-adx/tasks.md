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
- [x] T11 Deploy the module to dev and confirm the Flex app runs the timer
      (`FC1`/`FlexConsumption` verified live; automatic 06:30 tick advanced the
      cursor 15 -> 30 with no manual trigger)
- [x] T12 Re-verify ADX rows arrive from the Flex app's identity (45/45 correct)
- [x] T13a Stop the superseded Y1 app, halting the duplicate spend
- [ ] T13b Delete `func-aio-hvac-triage` + `EastUS2LinuxDynamicPlan` once the
      Flex app has run unattended long enough to satisfy the operator
- [x] T14 Confirm what-if reports no NEW deletes: `-60` is identical on this
      branch and on every prior run of `main`, so the count is pre-existing
      over-prediction rather than anything this feature introduces

## Fixed during live deployment

**`AzureWebJobsStorage` was missing from the module.** The app deployed,
registered both functions, reported `Running`, and never fired -- the Functions
host needs storage for trigger state and the timer's singleton lease. Granting
blob alone is not enough; the host uses queues and tables too. Deploying before
merging is what caught this, and a clean `bicep build` would never have.

## Open

1. **ADX cluster is currently un-imported.** The live cluster was portal-created and the
   template will create a *differently named* one (`dec...` vs `adxaiodevhvac`) rather
   than adopting it. Either import the existing cluster into the template's name, or
   accept a migration of the `hvac` data. Until that is decided, `dataExplorer.enabled`
   in dev deploys a second cluster — **T11 must confirm this is intended before merge.**
2. Function app deployment slots / staging are not modelled. Not needed for a timer, but
   worth revisiting if an HTTP surface is added.
