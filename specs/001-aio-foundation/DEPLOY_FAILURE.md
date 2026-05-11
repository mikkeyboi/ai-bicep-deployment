# Deploy Failure Report — 001-aio-foundation (env=dev)

**Date:** 2026-05-10 (MDT)
**Branch:** `001-aio-foundation` @ `b5fb0d7`
**Target:** subscription `Visual Studio Enterprise Subscription`, region `eastus2`
**Stage failed:** `az deployment sub validate` (pre-create)
**Resources created:** none. Resource group was not provisioned.
**Merge to main:** NOT performed.

## Symptom

`scripts/preflight.ps1` passed clean (no soft-deleted KV/CogSvc collisions).
`az deployment sub validate` then failed with:

```
InvalidTemplateDeployment / InsufficientQuota
This operation require 50 new capacity in quota
"One Thousand Tokens Per Minute - gpt-5-chat - GlobalStandard",
which is bigger than the current available capacity 0.
The current quota usage is 0 and the quota limit is 0
for quota One Thousand Tokens Per Minute - gpt-5-chat - GlobalStandard.
```

## Root cause

The current Visual Studio Enterprise subscription has **0 TPM quota for every
GlobalStandard chat-completion SKU** in `eastus2`, including:

| Quota family (eastus2)                       | Limit |
| -------------------------------------------- | ----- |
| `OpenAI.GlobalStandard.gpt-5-chat`           | 0     |
| `OpenAI.GlobalStandard.gpt-5`                | 0     |
| `OpenAI.GlobalStandard.gpt-5-mini` / `-nano` | 0     |
| `OpenAI.GlobalStandard.gpt-4o`               | 0     |

Datacentre/Standard tiers _do_ have quota, e.g.:

| Quota family (eastus2)                       | Limit |
| -------------------------------------------- | ----- |
| `OpenAI.Standard.gpt-4o`                     | 50    |
| `OpenAI.Standard.text-embedding-3-large`     | 350   |
| `OpenAI.Standard.gpt-4.1`                    | 50    |
| `OpenAI.DatazoneStandard.gpt-5.4-mini`       | 200   |

`infra/parameters/main.dev.bicepparam` requests:

```
gpt-5-chat              GlobalStandard / 50    ← no quota
gpt-4o                  Standard       / 50    ← OK
text-embedding-3-large  Standard       / 120   ← OK
```

So one of the three deployments is unfulfillable on this subscription, and
ARM rejects the entire template at validate time before any RG is created.

This is a subscription-quota issue, not a Bicep/template defect. The `gitleaks`,
`bicep build`, and previous local `what-if` passes did not exercise live Azure
quota; subscription-scope `validate` is the first stage that does.

## Fix options

### Option A — Request quota (preferred for an "AI foundation")

Open an Azure quota request:

> Help + support → New support request → Service & subscription limits (quotas)
> → Cognitive Services → request `OpenAI.GlobalStandard.gpt-5-chat` ≥ 50 K TPM
> in `eastus2` (and any other GPT-5 family SKUs you actually want).

Once granted, re-run:

```powershell
pwsh scripts/preflight.ps1 -SubscriptionId <id> -Location eastus2 -Environment dev
pwsh scripts/deploy.ps1    -Environment dev -Subscription <id> -Tenant <id> -Yes
```

### Option B — Slim dev params to what's already approved

Edit `infra/parameters/main.dev.bicepparam` to drop the `gpt-5-chat` entry,
leaving:

- `gpt-4o`                  `Standard`        50
- `text-embedding-3-large`  `Standard`        120

Optionally add `gpt-4.1` (`Standard`, 50) as a secondary chat model.

This would let `dev` deploy today and isolates the GPT-5 dependency to
`test`/`prod` env files (or behind a quota-request gate).

## What was NOT done

- No RG, KV, Foundry, OpenAI account, Search, Storage, AppInsights, MI, or LAW
  was created — validate failed before submission.
- No `IMPLEMENTATION_REPORT.md` deploy summary appended.
- No PR opened, no merge into `main`. Branch state unchanged except for this
  report.

## Suggested next step

Decide A vs B and re-trigger the deploy. Until then, leaving `001-aio-foundation`
unmerged is correct — merging code that cannot currently provision in `dev`
would violate the spec's "green deploy before merge" rule.
