# Research — 017

## Flex Consumption availability

`az functionapp list-flexconsumption-locations` includes **eastus2**, the workload's
primary region. `az functionapp list-flexconsumption-runtimes --location eastus2
--runtime python` lists 3.10 through 3.14.

## Runtime support windows (measured, not assumed)

| Python | Supported until |
|---|---|
| 3.10 | 2026-10-31 |
| 3.11 | 2027-10-31 |
| 3.12 | 2028-10-31 |
| 3.13 | 2029-10-31 |
| 3.14 | 2030-10-31 |

3.12 chosen: it outlives the 2028-09-30 Linux Consumption EOL, and the application code
is already 3.11-compatible so the jump is free. 3.13+ was not chosen because the
consuming repo pins 3.11 locally and a two-minor-version gap between local test and
deployed runtime is a real source of "works locally" defects.

## Flex differs from Consumption in ways that affect the template

- The plan (`serverfarm`) is a **real declared resource**. Under Y1 the platform created
  one implicitly; here `FC1`/`FlexConsumption` must be declared.
- Deployment uses a **blob container mount** via `functionAppConfig.deployment.storage`,
  not `WEBSITE_RUN_FROM_PACKAGE`. This is what allows a keyless deploy.
- `scaleAndConcurrency` replaces the old per-app scale settings.
- Several legacy `WEBSITE_*` app settings are rejected or ignored, so they are not set.

## Existing live SKUs (to reproduce, not invent)

- ADX: `Dev(No SLA)_Standard_E2a_v4`, tier `Basic`, capacity 1, East US 2.
- The live cluster carries **no tags** — evidence it was portal-created and never
  reconciled, which is what this feature fixes.

## Kusto RBAC boundary

Azure RBAC covers cluster *management*. Database-level **ingestor/viewer/admin**
principals are Kusto data-plane (`.add database <db> ingestors (...)`) and have no ARM
role-assignment equivalent. Confirmed against the live cluster: the function identity had
to be added via `execute_mgmt`, not `az role assignment create`. This is why the grant is
scoped out of the module rather than forgotten.
