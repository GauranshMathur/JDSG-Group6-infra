# ADR 0004 — Terraform plan on pull request, apply on merge

**Status:** Accepted — supersedes [ADR 0003](0003-terraform-runs-on-demand.md)
**Date:** 2026-08-18

## Context

ADR 0003, five days old, made `plan` and `apply` `workflow_dispatch`-only with a typed
confirmation on apply, on the instruction that neither should fire automatically. In use it
failed the purpose the pipeline exists for: nothing Terraform-related appeared on a pull
request, so the pipeline read as not existing at all, and exercising it meant knowing to go
find a manual workflow. Reviewed against the canonical references — HashiCorp's
[*Automate Terraform with GitHub Actions*](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
tutorial and community implementations of the same shape — the owner redirected to the
standard flow.

## Decision

**Plan is part of pull-request review; apply is what a merge means.** One workflow,
`terraform.yml`, path-scoped to `infra/terraform/**` and itself:

- **On a pull request:** `fmt -check` → `init` → `validate` → `plan` against a fresh floci
  emulator. The plan is posted on the pull request as a comment — one comment, updated in
  place on every push — and published as an artifact.
- **On a push to `main`** (i.e. a merge): the same steps, then `apply` of the plan file that
  run just produced.
- **On manual dispatch:** the plan half only, for an on-demand check between changes.

The typed confirmation is gone with the manual shape: the pull request review is the human
step, and merging is the confirmation. `fmt` and `validate` move out of `ci.yml` into this
workflow, so Terraform checks run exactly when Terraform changes.

## Cost

**Merge means apply, with no separate human step.** Here that costs nothing real — the
emulator is ephemeral and there is no AWS account — but in a real account this exact shape
is how infrastructure changes ship the moment someone merges. The production-shape
mitigation is a GitHub Environment with required reviewers on the apply job, not a typed
input; deliberately not added while nothing real is at stake, but that is the upgrade path.

**The plan reviewed is still not the plan applied.** The pull request's plan and the merge
run's plan describe two different emulator instances — the same limitation ADR 0003
recorded, unchanged, because the emulator is fresh every run. Within the merge run, the
plan file produced there is the one applied, which is as close as an ephemeral backend
allows.

**Path-scoping complicates I-1c.** A pull request that does not touch the Terraform gets no
Terraform check — correct scoping, but a *required* check that never starts is shown by
GitHub as pending forever. Making these checks required has to account for that.

## Alternatives considered

**Keeping ADR 0003's manual-only shape.** Rejected by the owner after seeing it: the
visibility was the point, and manual-only hid it. What ADR 0003 feared — apply-on-merge as
a habit — is answered by the Environment-protection upgrade path above rather than by
keeping apply off triggers entirely.

**HCP Terraform (Terraform Cloud), as the tutorial itself uses.** Rejected on mechanics,
not taste. Its remote runs execute on HashiCorp's own runners, which cannot reach a floci
emulator living on `localhost` inside our Actions job — and with no AWS account there is
nothing else for them to run against, so an apply could never succeed anywhere. Its
state-only mode ("local execution") would persist state for an emulator that does not
persist, making every plan a diff against a world that no longer exists. Worth revisiting
only if the target ever becomes a persistent local floci, where durable state is an asset
instead of a lie.

**Apply from the pull request itself.** No reference does this; apply belongs to the
default branch, or two open pull requests apply over each other.
