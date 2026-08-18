# CI/CD

GitHub Actions, in three workflows. A pull request shows **two checks at most**: `CI`,
always, and `Terraform` when the change touches `infra/terraform/**`.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | Every pull request | One job — workflow lint, Compose validation, Trivy scan (secrets, dependencies, misconfiguration) |
| `terraform.yml` | PRs touching the Terraform; pushes to `main` | `fmt` → `init` → `validate` → `plan`, plan posted on the PR; **apply on merge** — [ADR 0004](adr/0004-terraform-plan-on-pr-apply-on-merge.md) |
| `render-diagrams.yml` | Pushes to `main` touching a `.drawio` | Re-renders the architecture diagram to SVG |

It was briefly six checks, three of them Trivy in different costumes — a config scan in
`ci.yml`, a gating filesystem scan in a separate `security.yml`, and the code-scanning
check its SARIF upload created. One filesystem scan with `scanners: vuln,secret,misconfig`
over the whole tree does everything the three did, so now there is one. **What that cost:**
the SARIF report into GitHub's Security tab is gone — the scan still fails the build at the
same severities with the same scanners, but findings are read in the job log rather than a
tab. For a proof of concept, the gate is the part that matters.

## Why there is no routing

The app repository briefly had a parent pipeline routing to child pipelines by changed path,
because application and infrastructure code lived side by side and a Terraform change had no
business running RSpec. Splitting the repositories removed the decision entirely — everything
here is infrastructure — and with it the router, the aggregate gate job, and the router's own
test suite. Worth remembering as a general point: **a lot of pipeline complexity is a
monorepo cost**, not an inherent one.

The one path filter that exists is `terraform.yml`'s: it starts an emulator, which a
docs-only change has no business paying for. `ci.yml` runs on every pull request,
unconditionally.

## `ci.yml`

One job, three steps, cheapest first:

- **[`actionlint`](https://github.com/rhysd/actionlint)** catches what a YAML parser cannot —
  expression injection, invalid `needs:` references, deprecated syntax — and runs shellcheck
  over every `run:` block. It earned its place in the app repository by finding an unquoted
  command substitution feeding a secret into a container, in code that had already been
  reviewed.
- **`docker compose config`** validates the Compose files — interpolation, merges, unknown
  keys — without starting anything.
- **Trivy** scans the whole repository (`scan-ref: .`) for secrets, vulnerable dependencies
  and misconfiguration, failing on any fixable HIGH or CRITICAL. `ignore-unfixed` keeps the
  gate achievable: a finding with no upstream patch cannot be actioned by any change here,
  and failing on it would teach everyone to ignore the gate. This is also the scan that
  makes spike Terraform unmergeable — see below.

## `terraform.yml` — the Terraform pipeline

**The standard flow** ([ADR 0004](adr/0004-terraform-plan-on-pr-apply-on-merge.md)):
HashiCorp's own
[GitHub Actions tutorial](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions),
with floci standing in for HCP Terraform. A pull request that touches the Terraform is
planned; merging it applies.

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
```

The PR comment is the review surface: one comment per pull request, updated in place on
every push, carrying each step's outcome and the full plan in a collapsible section. `fmt`,
`validate` and `plan` continue through failure so the comment always reports all four, and
the job is failed explicitly afterwards.

**Merging is the confirmation.** ADR 0003 briefly made all of this manual-only with a typed
confirmation; ADR 0004 superseded it. The production note that survives: with a real
account, the guard on the apply job is a GitHub Environment with required reviewers. Here
nothing is real, so nothing gates it.

**Each run gets a fresh emulator, and that shapes everything else.** floci's state dies
with its container, so the pull request's plan describes an emulator instance that no
longer exists by the merge — the merge run plans again and applies the plan file *it*
produced. Within a run, what was published is what runs; across runs, the two plans can
only describe the same intent. And a fresh emulator is exactly the assertion being gated:
*this configuration stands up from nothing.*

**State still goes to S3, on the emulator, with `use_lockfile`.** Not for durability — the
bucket dies with the container — but because it is the real pattern, and the identical
configuration then works unchanged against a persistent local floci, where state genuinely
accumulates. The one ordering problem: the bucket must exist before `terraform init`, and
Terraform is what creates buckets, so the workflow bootstraps it with the AWS CLI first,
reading the name out of the backend block so the two cannot drift.

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
recorded. Worth a paragraph because the Terraform job inherits their findings.

**Neither could have been merged, and that is by design.** `ci.yml`'s Trivy scan covers the
whole repository (`scan-ref: .`) and fails on HIGH or CRITICAL, so throwaway Terraform —
which is deliberately unencrypted and unrestricted — turns `CI` red. A spike therefore
lives only on its pull request: open it, let CI run the experiment, read the answer, delete
the spike in the same pull request, merge green. Quieting the scanner to merge one would be
weakening a real gate for code that is about to be deleted.

The spike ran floci as a service container and applied a throwaway config against it,
answering the three questions in [`floci.md`](floci.md). The
[run](https://github.com/GauranshMathur/JDSG-Group6-infra/actions/runs/31680455895) is the
evidence; the config is in this repository's history at `8cc69a9`.

**What the Terraform job keeps from it.** A service container gets no Docker socket, and
with `FLOCI_SERVICES_EKS_MOCK=true` the EKS resources applied anyway — so the gate needs no
privileged access to the runner's daemon. And an `aws_lb` takes a full minute to create
against the emulator, so with two load balancers in the design, expect the job's duration
to be dominated by waiting rather than working; the timeout is set accordingly.

## Required status checks

`main` has none yet, so nothing gates a merge and auto-merge cannot arm. That is deliberate
for now. It changes with I-1c: `CI` and the Terraform plan become required. The apply can
never be among them — it runs *on* the merge, downstream of any gate — and requiring the
plan needs care, because the Terraform workflow is path-scoped and GitHub shows a required
check that never starts as pending forever.

## Versioning

This repository cuts no releases. The app repository derives a version from Conventional
Commits and publishes a container image; there is no equivalent artifact here, since Terraform
and manifests are applied rather than published. Whether that should change is in
[`open-questions.md`](open-questions.md).

Commits still follow Conventional Commits, because the history is easier to read that way and
because it keeps the option open.
