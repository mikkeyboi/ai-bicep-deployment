# Research: 004 East US Image Foundry

## D1 — Why a second account, not a second project?

In the unified Foundry resource model (Constitution v1.2.0):

- Model deployments are children of the **account**
  (`Microsoft.CognitiveServices/accounts` kind=`AIServices`), via
  `Microsoft.CognitiveServices/accounts/deployments`.
- An **account is single-region** (its `location` is fixed at create).
- A **project** (`accounts/projects`) is a portal-visible container that
  rides on its parent account; it does not own a separate region and
  cannot host model deployments independently of the account.

Therefore, to deploy models that exist only in eastus while keeping the
primary account in eastus2, a **second account in eastus** is required.
"A new project in eastus" is not expressible against an eastus2 account.

**Decision**: additive `secondaryFoundry` account + child project in eastus.

## D2 — Model availability (verified against Microsoft Learn, 2026-06)

| Model | format | version | SKU | eastus | eastus2 |
|---|---|---|---|---|---|
| `gpt-image-2` | `OpenAI` | `latest` → resolves `2026-04-21` | `GlobalStandard` | yes (region-supported) | no |
| `MAI-Image-2.5` | `Microsoft` | `2026-06-02` | `GlobalStandard` | **yes** | **no** |

> **gpt-image-2 deferred (2026-06-07):** CI preflight (`az deployment sub
> validate`, OIDC) returned
> `SpecialFeatureOrQuotaIdRequired: "the current subscription does not
> have access to this model 'Format:OpenAI,Name:gpt-image-2,
> Version:2026-04-21'"`. This is a per-subscription **limited-access
> registration** gate (`aka.ms/oai/access`), distinct from quota — the
> operator's existing manual eastus2 gpt-image-2 deployment does not
> grant template-deploy access here. The model is region-supported in
> eastus, so it remains in `region-capabilities.bicep`; only its dev
> paramfile entry is commented out until access is approved. `MAI-Image-2.5`
> validated past preflight and deploys now.

MAI image global-standard regions per Microsoft Learn ("Deploy and use
MAI image models in Microsoft Foundry"): West Central US, **East US**,
West US, West Europe, Sweden Central, South India, UAE North. eastus2 is
not listed — this is the concrete reason the primary region cannot host
these models.

**Caveat**: `az`/`bicep` are not installed in the authoring environment,
so the live `az cognitiveservices model list --location eastus` check is
deferred to the operator / CI (which has `az login`). This mirrors how
the original `region-capabilities.bicep` map was built (each entry was
verified with that command). `gpt-image-2` is wired as version
`latest` (the module maps `'latest'` → `null`, letting Azure resolve the
current GA version) until a dated version is confirmed.

## D3 — `format=Microsoft` and Constitution VIII

`MAI-Image-2.5` is a **Microsoft MAI** model "sold directly by Azure"
(a.k.a. Azure Direct Models). These bill through the Azure subscription
as consumption, are covered by Azure SLAs, and do **not** require an
Azure Marketplace "Subscribe" step. They are therefore allowed under
Principle VIII, unlike partner/Marketplace models (Anthropic Claude,
Cohere, Mistral premium) which remain forbidden.

`modelFormat` is widened from `'OpenAI'` to `'OpenAI' | 'Microsoft'`.
It is deliberately NOT widened to partner formats, preserving the
Principle VIII guardrail at the type level.

## D4 — API-key re-enablement (Security-section deviation)

The existing `foundry-account` module already exposes
`param disableLocalAuth bool = true`. Re-enabling keys is a paramfile
change (`secondaryFoundry.disableLocalAuth = false`) threaded through the
typed config — no hardcoded literal in any module (Principle IV).

Trade-off (logged in plan.md Complexity Tracking): keys are a weaker
auth posture than managed identity. Mitigations: scoped to the eastus
account only; UAMI keeps `Cognitive Services User` so Entra auth still
works in parallel; keys never emitted/committed; revertible by flipping
one boolean. The image REST samples (`api-key:` header) are the concrete
use case driving the request.

## D5 — Naming collision check

`foundry()` and `project()` build names as
`<abbr>-<workload>-<env>-<regionShort>[-<instance>][-<hash>]`.
- eastus2 account: `aif-aio-dev-eus2-<hash>`
- eastus account:  `aif-aio-dev-eus-<hash>`

Different `regionShort` segment (`eus2` vs `eus`) guarantees distinct
names. Verified `eastus: 'eus'` is already present in `regionMap`.

## D6 — Capacity

Image models default to a small quota (≈5 images/min). `GlobalStandard`
capacity is set to `1` for both (the Microsoft CLI sample uses
`--sku-capacity 1`). Raise per quota once the deployment is live.
