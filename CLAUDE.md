# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

The infrastructure for a Twitter/X-style app whose code lives in
[JDSG-Group6-app](https://github.com/GauranshMathur/JDSG-Group6-app). An enterprise AWS
architecture is the *reference design*; it is realized entirely locally. **There will never
be a real AWS account, and no real cloud resource is ever created — not to test something,
not ever.** Terraform targets the AWS provider pointed at a local emulator (floci), so real
AWS would be an endpoint change, not a rewrite.

Two pieces, one repo:

- **The system**: the app running on a local k3d cluster — real PostgreSQL, real object
  storage, Traefik. Anything runtime-shaped (load, resiliency) happens here.
- **The companion artifact**: the reference design as Terraform under `infra/terraform/`,
  verified in CI against floci. It proves the config stands up; it never runs the app.

Docs: [docs/architecture.md](docs/architecture.md) (the design),
[docs/decisions.md](docs/decisions.md) (what was decided and what's still open),
[docs/floci.md](docs/floci.md) (the emulator's real depth).

## How to work here

- **Keep it simple.** This repo was once buried under its own process; it was reset on
  2026-08-18. A decision is a dated paragraph in `docs/decisions.md`, not a new file or an
  ADR. Prefer deleting documentation to adding it. Do not scaffold ahead of what the
  current work needs.
- When a decision is genuinely open, ask rather than guessing; open items live at the
  bottom of `docs/decisions.md`.
- One root, no modules; Terraform files split by concern; Kubernetes objects are
  manifests, never `kubernetes` provider resources. Never commit state.
- Manifests stay cluster-agnostic — no EKS-only storage classes, no ALB annotations.
- No application code here; it belongs in the app repository.
- Do not weaken a CI security gate to make a build pass. If a finding is genuinely not
  actionable, say so and ask.

## Conventions

- [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`,
  imperative, lowercase, no trailing period.
- All work reaches `main` through a pull request on a `type/<short-description>` branch —
  never commit to `main` directly, never use an environment-assigned branch name.
- Run what CI runs before pushing (`terraform fmt/validate/plan`, compose config).

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, named as-is (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the repo root (created lazily by `/domain-modeling`) plus
decision records in `docs/decisions.md`. See `docs/agents/domain.md`.
