# CI/CD

GitHub Actions, in four workflows. All of them are small, because this repository holds one
kind of thing.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | Pull requests | Workflow lint, Compose validation, misconfiguration scan |
| `terraform.yml` | PRs touching the Terraform; pushes to `main`; manual `plan` | `fmt` → `validate` → `plan` against floci, plan posted on the PR; **apply on merge** — [ADR 0004](adr/0004-terraform-plan-on-pr-apply-on-merge.md) |
| `security.yml` | Pull requests | Trivy filesystem scan — secrets, dependencies, misconfiguration |
| `render-diagrams.yml` | Pushes to `main` touching a `.drawio` | Re-renders the architecture diagram to SVG |

## Why there is no routing

The app repository briefly had a parent pipeline routing to child pipelines by changed path,
because application and infrastructure code lived side by side and a Terraform change had no
business running RSpec. Splitting the repositories removed the decision entirely: everything
here is infrastructure, so one pipeline runs and nothing is ever skipped.

That also removes the machinery the routing needed — a router, an aggregate gate job to avoid
required-check deadlock, and a test suite for the router itself. Worth remembering as a
general point: **a lot of pipeline complexity is a monorepo cost**, not an inherent one.

The one path filter that does exist is `terraform.yml`'s: it starts an emulator, which a
docs-only change has no business paying for. Everything in `ci.yml` and `security.yml`
still runs on every pull request.

## `ci.yml`

**Workflow lint** runs [`actionlint`](https://github.com/rhysd/actionlint), which catches what
a YAML parser cannot — expression injection, invalid `needs:` references, deprecated syntax —
and runs shellcheck over every `run:` block, so the bash in these workflows is linted rather
than read by eye. It earned its place in the app repository by finding an unquoted command
substitution feeding a secret into a container, in code that had already been reviewed.

**Compose files** are validated with `docker compose config`, which resolves interpolation and
merges and rejects unknown keys without starting anything.

**Misconfiguration scan** runs Trivy's config scanner over `infra/`. It finds little today,
because `infra/` holds two Compose files. It is here so that the first Terraform commit lands
in front of a gate that already exists, rather than one added afterwards once something has
already slipped through.

## `terraform.yml` — the Terraform pipeline

**The standard flow** ([ADR 0004](adr/0004-terraform-plan-on-pr-apply-on-merge.md), the
shape of HashiCorp's own
[GitHub Actions tutorial](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)):
a pull request that touches the Terraform is planned, and merging it applies.

```
On a pull request touching infra/terraform/** (or this workflow):
  (bootstrap the state bucket)          → AWS CLI, before init
  terraform fmt -check -recursive
  terraform init                        # S3 backend on floci
  terraform validate
  terraform plan -out=tfplan            → uploaded as an artifact, AND
                                          posted on the PR as a comment

On a push to main touching the same paths (i.e. a merge):
  the same steps, then
  terraform apply tfplan                → the plan produced in this run

On workflow_dispatch: the plan half only — an on-demand check.
```

The PR comment is the review surface: one comment per pull request, updated in place on
every push, carrying each step's outcome and the full plan in a collapsible section. `fmt`,
`validate` and `plan` continue through failure so the comment always reports all four, and
the job is failed explicitly afterwards.

**Merging is the confirmation.** ADR 0003 briefly made all of this manual-only with a typed
confirmation; ADR 0004 superseded it. What survives from that record is its analysis, and
one production note: with a real account, the guard on the apply job is a GitHub
Environment with required reviewers — a merge should not reach real infrastructure without
one. Here nothing is real, so nothing gates it.

Three things about the shape:

**Plan and apply cannot share a file across runs, because each run gets a fresh emulator.**
floci's state dies with its container, so the pull request's plan describes an emulator
instance that no longer exists by the merge. The merge run therefore plans again and
applies the plan file *it* produced — within the run, what was published is what runs;
across runs, the two plans can only describe the same intent. ADR 0004 carries this
forward from ADR 0003 without pretending otherwise.

**floci runs as a service container, fresh every run.** That means every apply starts from
nothing, which is exactly the assertion: *this configuration stands up against a clean
emulator*. Persisting state between runs would be worse than useless — Terraform would refresh
state describing resources that no longer exist and plan to recreate everything.

**State still goes to S3, on the emulator.** Not for durability — the bucket dies with the
container — but because it is the real pattern, and because the identical configuration then
works against a persistent local floci, where state genuinely accumulates and incremental
applies do what you want. Terraform 1.10+ gives S3-native locking with `use_lockfile`, so
there is no DynamoDB lock table.

One ordering problem, now handled: the state bucket must exist before `terraform init`, and
Terraform is what creates buckets. The workflow bootstraps it with the AWS CLI before init,
reading the bucket name out of the backend block so the two cannot drift, and failing loudly
if it cannot find one.

**GitHub has no managed state backend.** GitLab ships one — an HTTP backend with encryption,
locking and versioning, authenticated against GitLab roles. GitHub has no equivalent, so S3 is
not a second-best choice here; it is the choice, and it happens to be the one the reference
design already calls for.

## `security.yml`

Separate from `ci.yml` so that it is obviously never conditional.

It is also what makes the `Trivy` code-scanning check appear on every pull request. That check
is created by the SARIF upload rather than being a job, so if the only upload lived in a
conditional job, any pull request that skipped it would show the check as expected and waiting
for a status that never arrives — which reads exactly like a job refusing to be scheduled.

Each scan runs twice: once to gate, filtered to HIGH and CRITICAL with an exit code, and once
to report every severity as SARIF into the Security tab. The reporting pass is `if: always()`,
so a failing gate still publishes what it found.

## `render-diagrams.yml`

The architecture diagram is authored as draw.io XML and edited online in app.diagrams.net,
which commits the `.drawio` straight back to `main`. GitHub cannot render draw.io files, so
the README embeds an SVG — and an SVG exported by hand goes stale the first time someone edits
the diagram and forgets to re-export.

So the export is a workflow: any push to `main` touching a `.drawio` under `docs/diagrams/`
re-renders it, and commits the result back as `github-actions[bot]` if it differs. The commit
message carries `[skip ci]`, and pushes from the built-in `GITHUB_TOKEN` do not retrigger
workflows anyway — no recursion by two independent mechanisms.

This is the one workflow that pushes to `main` directly rather than going through a pull
request. That is deliberate: the SVG is derived output, not authored work. Reviewing it would
mean reviewing a rendering.

## The spike workflows — existed, and are gone

Two of them: `spike-floci.yml` answered I-1a's three questions, and
`spike-cloudfront-provider.yml` bisected six AWS provider versions to prove the CloudFront
crash is not a recent regression. Both were deleted the moment their answers were
recorded. Worth a paragraph because I-1b's Terraform job inherits their findings.

**Neither could have been merged, and that is by design.** `security.yml` scans the whole
repository (`scan-ref: .`) and fails on HIGH or CRITICAL, so throwaway Terraform — which is
deliberately unencrypted and unrestricted — turns `Security` red. A spike therefore lives
only on its pull request: open it, let CI run the experiment, read the answer, delete the
spike in the same pull request, merge green. Quieting the scanner to merge one would be
weakening a real gate for code that is about to be deleted.

It ran floci as a service container and applied a throwaway config against it, answering
the three questions in [`floci.md`](floci.md), and was deleted the moment those answers
were recorded — a throwaway probe that outlives its question becomes a workflow nobody
dares touch. The
[run](https://github.com/GauranshMathur/JDSG-Group6-infra/actions/runs/31680455895) is the
evidence; the config is in this repository's history at `8cc69a9`.

**What the Terraform job should keep from it.** A service container gets no Docker socket,
and with `FLOCI_SERVICES_EKS_MOCK=true` the EKS resources applied anyway — so the gate
needs no privileged access to the runner's daemon. And an `aws_lb` takes a full minute to
create against the emulator, so with two load balancers in the design, expect the job's
duration to be dominated by waiting rather than working; set the timeout accordingly.

## Required status checks

`main` has none yet, so nothing gates a merge and auto-merge cannot arm. That is deliberate
for now. It changes with I-1c: the scans and the Terraform plan become required. The apply
can never be among them — it runs *on* the merge, downstream of any gate — and requiring
the plan needs care, because the Terraform workflow is path-scoped and GitHub shows a
required check that never starts as pending forever.

## Versioning

This repository cuts no releases. The app repository derives a version from Conventional
Commits and publishes a container image; there is no equivalent artifact here, since Terraform
and manifests are applied rather than published. Whether that should change is in
[`open-questions.md`](open-questions.md).

Commits still follow Conventional Commits, because the history is easier to read that way and
because it keeps the option open.
