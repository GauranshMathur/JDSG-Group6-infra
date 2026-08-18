# ADR 0003 — `terraform plan` and `apply` run on demand, not on a trigger

**Status:** Accepted
**Date:** 2026-08-13

## Context

[ADR 0001](0001-terraform-verifies-runtime-deploys.md) argued that because floci starts in
milliseconds and needs no Docker socket, *"`terraform apply` must succeed against a clean
emulator" becomes a CI gate rather than something someone ran once* — run on every change.
`REQUIREMENTS.md` I-2.6 recorded the same intent.

Running `apply` automatically is a habit worth not forming. It is harmless here — the
emulator is ephemeral and there is no AWS account — but the pipeline is written to be the
shape a real one would take, and in a real one an `apply` fired by a merge is how
infrastructure gets changed by accident. The value of the emulator gate is that the
configuration *can* stand up, and that question does not need answering on every
documentation typo.

## Decision

**`plan` and `apply` are `workflow_dispatch` only.** `.github/workflows/terraform.yml` has
no `pull_request` or `push` trigger. `apply` additionally requires typing `APPLY` into a
confirmation input, checked before anything else runs.

**`fmt -check` and `validate` stay automatic**, in `ci.yml`, when the Terraform lands.
They need no emulator, create nothing, and are the checks that actually want to run on
every change.

**Plan and apply share one run**, because they must share an emulator. floci is fresh
every run and its state dies with it, so a plan produced in an earlier run describes state
that no longer exists. `apply` therefore plans and applies in the same job, consuming the
plan file it just wrote rather than re-planning — which preserves the "apply the plan you
published" property from [`ci-cd.md`](../ci-cd.md) within the run.

## Cost

**Nothing catches a broken configuration automatically any more.** A pull request can
merge with Terraform that does not plan, and nobody finds out until someone runs the
workflow. That is the real price, and it is paid in exchange for a pipeline whose shape
does not teach the wrong habit. Partly mitigated by `fmt`/`validate` staying automatic,
which catches syntax and schema errors but not dependency, provider or ordering failures.

**Reviewing a plan before applying it is weaker than it looks.** Because state cannot
survive between runs, "run `plan`, read the artifact, then run `apply`" means the apply
re-plans against a clean emulator — so what you reviewed and what runs are two different
plan files that happen to describe the same intent. Within a single `apply` run the
published plan *is* the applied plan; across runs it is not, and no amount of artifact
plumbing fixes that while the emulator is ephemeral.

**Someone has to remember.** A gate nobody triggers is a gate that does not exist. If
I-1b's Terraform stops applying cleanly, this decision is why it took a while to notice.

## Alternatives considered

**Automatic on pull request**, as ADR 0001 assumed. Rejected by this record: it is the
habit worth not forming, and it spends a floci-backed run on every change to a
`.md` file. Note that `ci.yml` is not path-filtered in this repository, so it would have
been every change, not every Terraform change.

**Automatic `plan`, manual `apply`.** The conventional split, and genuinely tempting: it
keeps the "does this still stand up" signal on every pull request while keeping the
destructive half deliberate. Rejected for now because a plan against a *clean* emulator
with no prior state is close to a `validate` with extra steps — it can only ever say "all
resources would be created" — so it buys less here than it would against persistent state.
**Worth revisiting the moment the emulator persists between runs**, at which point plan
becomes a real diff and this trade changes.

**Persist the emulator between runs** so plan and apply can be separate, reviewable steps.
Rejected as more machinery than I-1b needs, and it undermines the assertion the gate
exists to make: that the configuration stands up *from nothing*.
