# Tasks — 003 Matrix Bridge

Phase A — types & naming
- T001 Extend `infra/shared/types.bicep` with `matrixConfig` and
  add `enableMatrix` + `matrix?` to `environmentConfig`.
- T002 Extend `infra/shared/naming.bicep` with `cae` (ACA env) and
  `ca` (Container App) helpers.

Phase B — modules
- T010 `infra/modules/matrix/file-share.bicep`.
- T011 `infra/modules/matrix/environment.bicep`.
- T012 `infra/modules/matrix/homeserver.bicep`.

Phase C — config template
- T020 `config/matrix/continuwuity.toml` (reference template; the live
  config is composed entirely via env vars on the container so this is
  documentation-only for v1).

Phase D — wiring
- T030 Wire modules into `infra/workload.bicep` behind `enableMatrix`.
- T031 Extend `main.bicep` outputs.
- T032 Update `main.dev.bicepparam`: `enableMatrix: true`, `matrix: {
  hostname: readEnvironmentVariable('MATRIX_HOSTNAME', ''), ... }`.
- T033 Update `main.test.bicepparam` / `main.prod.bicepparam` (if they
  exist) with `enableMatrix: false`.
- T034 Update `scripts/deploy.ps1` with `-MatrixHostname` param that
  exports `$env:MATRIX_HOSTNAME` for the duration of the run.
- T035 Update `.github/workflows/deploy.yml` and `validate.yml` to pass
  `MATRIX_HOSTNAME: ${{ vars.MATRIX_HOSTNAME }}` to the az cli step.

Phase E — validate
- T040 `bicep lint infra/main.bicep`.
- T041 `bicep build infra/main.bicep`.
- T042 `az deployment sub validate` (dev).
- T043 `az deployment sub what-if` (dev).
- T044 `gitleaks detect`.
- T045 Privacy grep (operator domain, tenant id, sub id, emails, token
  shapes) → zero hits.

Phase F — GH config + commit + PR
- T050 `gh variable set MATRIX_HOSTNAME --env dev --body
  "matrix.<operator-domain>"`.
- T051 Commit, push, open PR, merge to main.
