# AI-Bicep-Deployment Constitution

> Governing principles for the `mikkeyboi/ai-bicep-deployment` repository.
> All specifications, plans, tasks, and code must comply. Violations require an
> entry in the **Complexity Tracking** table of the relevant `plan.md`.

## Core Principles

### I. Declarative & Idempotent (NON-NEGOTIABLE)
Infrastructure is expressed only in Bicep. The same template applied twice
produces no change. Imperative scripting (`az resource create ...`) is
forbidden in deployment paths; scripts may only orchestrate (`az deployment sub create`),
gather inputs, or assert post-conditions. Every deployment runs `what-if`
before `create`.

### II. No Secrets, No Identifiers, No Personal Data in Source
The repository is **public**. The following must never appear in committed
files (including history):
- Tenant IDs, subscription IDs, object IDs, principal IDs
- API keys, connection strings, SAS tokens, passwords
- User principal names, email addresses, real person names beyond the
  GitHub handle of the repo owner
- Resource names that embed any of the above

All such values are injected at deploy time from GitHub **Variables**
(non-sensitive identifiers) or **Secrets** (credentials), or from the local
shell when running outside CI. A pre-commit secret scan and a `gitleaks`
GitHub Action enforce this. CI logs must not echo secret values.

### III. OIDC-First Authentication
GitHub Actions authenticates to Azure via **workload identity federation
(OIDC)**. Long-lived client secrets and service principal passwords are
prohibited for CI. Local development uses the operator's existing
`az login`. The federated app registration is scoped to this repository
and to a specific subscription with the minimum role required (default:
`Contributor` + `User Access Administrator` on the target resource group
scope only when role assignments are deployed).

### IV. Modular Templates with a Single Entry Point
- One `main.bicep` per deployment scope (subscription-scope for top-level,
  resource-group-scope for workload modules).
- Reusable resources live under `infra/modules/<resource-family>/` and
  expose typed parameters and explicit outputs only — no implicit
  cross-module coupling.
- Naming, tagging, and shared types live in `infra/shared/` and are
  consumed via `import` or module reference, never copy-pasted.
- Hardcoded values (regions, SKUs, model names, capacities) are forbidden
  in modules. They flow from `main.bicepparam` → `main.bicep` → modules.

### V. Naming & Tagging Discipline
All resource names are produced by the central naming function in
`infra/shared/naming.bicep`, which implements the
[Cloud Adoption Framework abbreviation table](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
and the pattern `<abbr>-<workload>-<env>-<region-short>[-<instance>]`.
Every resource carries the standard tag set (`environment`, `workload`,
`owner`, `costCenter`, `managedBy=bicep`, `repo`, `deployedAt`).

### VI. Validation Gates Before Deploy
Pull requests run, and must pass, in order:
1. `bicep lint` (no warnings allowed at error level)
2. `bicep build` (compilation clean)
3. `az deployment <scope> validate`
4. `az deployment <scope> what-if` (posted as a PR comment)
5. `gitleaks` secret scan
Deployment to any environment runs only from the default branch after
merge, gated by GitHub **environments** with required reviewers for
non-`dev` targets.

### VII. Environment Parity & Parameterization
The same Bicep modules deploy `dev`, `test`, and `prod`. Differences are
expressed only in `main.<env>.bicepparam` files. A new environment is
added by creating a parameter file and a GitHub environment — never by
forking templates.

## Security & Compliance Requirements

- **Key Vault is mandatory** for any secret material an application
  produces or consumes. RBAC mode (`enableRbacAuthorization: true`),
  purge protection on for `prod`.
- **Managed identity over keys** for all service-to-service auth where
  the resource supports it (Storage, Key Vault, OpenAI, AI Search,
  Foundry).
- **Diagnostic settings** routing to a Log Analytics workspace are
  required on every PaaS resource that supports them.
- **Public network access** defaults to `Disabled` for `prod`; `dev` may
  enable it but must restrict by IP allowlist when feasible.
- **Model deployments** record their content filter policy explicitly;
  defaults are not assumed.

## Development Workflow

- **Spec-Driven**: every change starts as a spec under `specs/NNN-*/`
  and proceeds through plan → tasks → implement. Direct edits to
  `infra/` without a corresponding spec are rejected in review.
- **Trunk-based**: short-lived feature branches `NNN-<slug>`, squash
  merge to `main`. No long-running release branches.
- **Conventional Commits** with scopes `infra`, `ci`, `docs`, `spec`,
  `scripts`.
- **PR template** must include: linked spec, `what-if` diff summary,
  affected environments, rollback plan.
- **Local parity**: `scripts/deploy.ps1` and `scripts/deploy.sh` accept
  `-Subscription`, `-Tenant`, `-Environment`, `-Location` and run the
  same `what-if`/`create` sequence the CI uses. No flag has a default
  that hardcodes a tenant or subscription.

## Governance

This constitution supersedes ad-hoc conventions. Amendments require a PR
that updates this file, bumps the version below per semver
(MAJOR = principle removed/redefined, MINOR = principle added,
PATCH = wording/clarification), and lists the migration impact on existing
specs. All PRs and reviews must verify compliance; reviewers cite the
violated principle by number when requesting changes. Runtime guidance
for AI agents lives in `.github/copilot-instructions.md` and must remain
consistent with this document.

**Version**: 1.0.0 | **Ratified**: 2026-05-10 | **Last Amended**: 2026-05-10
