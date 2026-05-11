# Implementation Plan: 002 New Foundry

**Branch**: `002-new-foundry` | **Date**: 2026-05-10
**Spec**: [spec.md](./spec.md) | **Constitution**: v1.2.0

## Summary

Refactor: replace hub-based AI Foundry (`Microsoft.MachineLearningServices/
workspaces` kind=Hub+Project) with the unified Foundry resource
(`Microsoft.CognitiveServices/accounts` kind=AIServices + child
projects). Models move from the sidecar `kind=OpenAI` account onto the
Foundry account itself. Storage, KV, AI Search, LAW, App Insights, and
the workload UAMI are reused without change.

## Directory Diff

```
infra/
  modules/
    foundry-account/      [NEW]
      main.bicep
      project.bicep
    foundry-hub/          [DELETED]
    foundry-project/      [DELETED]
    foundry-connection/   [DELETED]
    openai-account/       [DELETED — consolidated onto Foundry account]
    openai-deployment/    [DELETED — superseded by foundry-account/deployment]
  main.bicep              [MODIFIED — outputs swapped]
  workload.bicep          [MODIFIED — wiring rewritten]
  shared/
    naming.bicep          [MODIFIED — `foundryAccount` helper exported, hub/project helpers retained but unused]
    types.bicep           [MODIFIED — drop connectionSpec; keep modelDeployment]
  parameters/
    main.dev.bicepparam   [MODIFIED — drops openAi.* shape; adds foundry.{ ... }]

specs/002-new-foundry/    [NEW]
.specify/memory/constitution.md  [MODIFIED — bumped to 1.2.0]
```

## Constitution Check (v1.2.0)

| Principle | Compliance | Notes |
|---|---|---|
| I. Declarative & Idempotent | PASS | Pure Bicep + what-if before create. |
| II. No Secrets / IDs / PII | PASS | No tenant/sub/email touched in this feature. |
| III. OIDC-First | PASS | No CI auth changes. |
| IV. Modular Templates / Single Entry | PASS | One new `foundry-account` module; new clarification (AI Foundry = AIServices RP) honored. |
| V. Naming & Tagging | PASS | Adds `foundryAccount` helper using existing `aif-` abbreviation. |
| VI. Validation Gates | PASS | lint + build + validate + what-if + gitleaks before deploy. |
| VII. Environment Parity | PASS | Only dev paramfile changes in this feature; test/prod scaffolds unchanged. |
| VIII. Consumption Billing | PASS | `Microsoft.CognitiveServices` kind=AIServices, child projects, child deployments — all consumption. |

## Phases

- **Phase 0**: Spec amendment (this directory + constitution bump).
- **Phase 1**: New module + workload rewiring.
- **Phase 2**: Validate (lint/build/validate/what-if/gitleaks/grep).
- **Phase 3**: Tear down old resources, deploy, smoke check.
- **Phase 4**: Merge + sanitized DEPLOY_REPORT_002.md.
