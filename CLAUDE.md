# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this project is

The infrastructure for a Twitter/X-style social application. The application itself lives in a
separate repository, [JDSG-Group6-app](https://github.com/GauranshMathur/JDSG-Group6-app);
this one holds the reference design, the Terraform, the Kubernetes manifests, and the
decisions behind them.

**It is a proof of concept, and there will never be a real AWS account.** The enterprise AWS
architecture is the *reference design* — drawn and written as a real account would be — and it
is realized entirely locally. Where a decision trades production robustness for something
working and understandable, take the second, and say so at the point you take it rather than
leaving it to be discovered.

**Never create real cloud resources.** Not as a side effect, not to test something, not ever.
Terraform is written against the AWS provider so that pointing at real AWS would be an
endpoint change rather than a rewrite — that is the whole of the relationship with AWS.

Where things are written down:

| File | What it holds |
| --- | --- |
| `README.md` | What this is and how to run it. Keep it short — prose belongs in `docs/` |
| `REQUIREMENTS.md` | Numbered requirements and whether each is met. Update the status when a requirement's state actually changes |
| `docs/infrastructure.md` | The reference design, layer by layer, and its local realization |
| `docs/floci.md` | The emulator: how deep each service goes, and what that forces |
| `docs/roadmap.md` | The I-1 milestones, in two tracks |
| `docs/ci-cd.md` | This repository's pipeline |
| `docs/open-questions.md` | Decisions not yet taken, each with why it matters and when it is needed |
| `docs/adr/` | Decision records — why a choice was made, and what it cost |

## The relationship with the app repository

- **This repository never contains application code.** If a change needs a Rails file edited,
  it belongs in the app repository, and the two land as separate pull requests.
- **The app repository never describes its deployment.** It publishes a container image to
  GHCR; everything about where that image runs is here.
- **The image is the whole interface.** `ghcr.io/gauranshmathur/twitter-clone-web`, tagged with
  a version and an immutable `sha-<commit>`.
- Three app changes are owed to this milestone — PostgreSQL, a shared cache, and S3 media —
  recorded in `docs/infrastructure.md`. They are made **in the app repository**, when they
  block, not before.

## Current milestone

**I-1a is done; I-1b is next and unblocked.** The design and diagram exist, and all four
toolchain questions are answered — the EKS module one by reading the module, the other
three by a throwaway verification spike applying Terraform against floci in CI. What it
measured is in `docs/floci.md`; the headlines are that the inert tier really does apply,
EKS mock mode needs no Docker socket, and unimplemented operations fail loudly rather than
faking success.

**Two findings constrain I-1b, and neither was predicted.** CloudFront **cannot be applied
at all** — floci accepts the create and returns an object that segfaults the AWS provider
on read-back, on every provider version from 4.67 to 6.59. EC2 placement groups are
refused outright. CloudFront is **decided**: omitted from the Terraform, with the reason
stated wherever the design describes the edge
([ADR 0002](docs/adr/0002-cloudfront-omitted-from-terraform.md)).

**One decision is still open before the cluster's Terraform (`eks.tf`) is written**, in
`docs/open-questions.md`: whether it is the community EKS module with
floci-specific overrides or hand-rolled. I-1b's other slices do not depend on it. It is
not a compatibility question — the module is two variables from applying
(`encryption_config = null`, `enable_irsa = false`) — but a choice about whether to accept
a cluster that no longer matches the reference design. It gets an ADR.

**The work is two independent tracks — [ADR 0001](docs/adr/0001-terraform-verifies-runtime-deploys.md).**

- **Track A, Terraform (taken first).** The reference design written as Terraform and applied
  against floci. This proves the config stands up; it never runs the app. One root, no
  modules, files split by concern. Terraform stops at AWS — Kubernetes objects stay as
  manifests. The pipeline is the standard flow
  ([ADR 0004](docs/adr/0004-terraform-plan-on-pr-apply-on-merge.md), superseding ADR 0003's
  manual-only shape): every pull request touching the Terraform gets `fmt` → `validate` →
  `plan` against a fresh emulator with the plan posted as a PR comment, and merging it
  applies. `terraform.yml` is the only path-scoped workflow, because it starts an emulator.
- **Track B, runtime.** A real local Kubernetes cluster (k3d) running the app, and where load
  and stress testing happen. Real PostgreSQL, real object storage, real ingress. Nothing here
  depends on floci.

Why split: floci runs real engines for a few services (EKS→k3s, RDS→PostgreSQL) and answers
the API while doing nothing for the rest — including the whole network and both load
balancers. Betting the deployment on the first tier being deep enough is the risk the split
removes. It costs a single end-to-end demo, and leaves two descriptions of the cluster that
can drift; keep manifests cluster-agnostic.

## How we work here

- Built **incrementally, one slice at a time**. Do not scaffold ahead of the current
  milestone — no Terraform for a service the milestone does not need.
- **Each milestone is built, tested and merged before the next one starts**, on its own branch
  with its own pull request.
- When a decision is genuinely open, ask rather than guessing. Add it to
  `docs/open-questions.md` with why it matters and when it needs answering.
- A decision with a real alternative and a cost worth remembering gets an ADR in `docs/adr/`.
  One with no genuine alternative is just a line in the document it affects. An ADR that lists
  only benefits is marketing — record what the choice cost.
- `docs/open-questions.md` is a live list, not an append-only log. When work answers a
  question, delete it and move the answer into the document it belongs to.

## Conventions

**Terraform**

- **One root, no modules.** Modules earn their keep when the same shape is instantiated more
  than once; there is one of everything here, and floci has no region isolation, so even the
  DR region never becomes a second instantiation.
- Files split by concern — `network.tf`, `eks.tf`, `rds.tf`, `s3.tf`, `iam.tf`.
- **Terraform stops at AWS.** Kubernetes objects are manifests, not `kubernetes` provider
  resources: the provider cannot plan against a cluster that does not exist yet, which forces
  two-phase applies.
- **Inert resources are applied and labelled.** Most of the reference design creates cleanly
  against floci and then does nothing — the whole network, both load balancers, WAF. Apply
  them so the Terraform matches the diagram, and mark them so nobody reads a Web ACL in the
  state file as something that filters traffic.
- **CloudFront is the one exception, and it is not a matter of taste**
  ([ADR 0002](docs/adr/0002-cloudfront-omitted-from-terraform.md)). floci accepts
  `CreateDistribution` and returns an object that segfaults the AWS provider on read-back,
  on every provider version from 4.67 to 6.59. It is omitted from the Terraform and the
  omission is stated wherever the design describes the edge. Do not add it back expecting
  it to work, and do not generalise the exception to anything else.
- Never commit state. State lives in the emulator's S3.

**Kubernetes**

- Manifests stay **cluster-agnostic**: no EKS-specific storage classes, no ALB ingress
  annotations. Two descriptions of the cluster exist and can drift; this is the only thing
  keeping them honest.

**Commits**

- [Conventional Commits](https://www.conventionalcommits.org/) — `type(scope): subject`.
- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`.
- Subject in the imperative mood, lowercase, no trailing period.

**Branches and pull requests**

- All work reaches `main` through a pull request. Do not commit to it directly.
- Branch names: `feat/<short-description>`, `fix/<...>`, `docs/<...>`, matching the commit type.
  **Never use an environment-assigned branch name** (e.g. `claude/repo-review-*`) — create your
  own from `main`.
- CI is the review gate: a pull request is ready when the pipeline is green.
- Run what CI runs before pushing. A CI failure a local run would have caught wastes a pipeline.

## Things to leave alone

- **Never create real cloud resources.** The deployment is local by design.
- **I-1a's toolchain questions are answered**, so the rule that once blocked Terraform here
  has been discharged. It is kept in shortened form because it was reworded to escape a
  deadlock and the reasoning is worth not repeating: the ban was on Terraform *for the
  reference design*, never on a throwaway verification spike — those questions could only be
  settled by an apply, and an apply needs Terraform. Any future spike follows the same shape:
  minimal, under `spike/`, gating nothing, deleted once its answers are recorded.
- **A spike is run on a pull request and deleted before that pull request merges.** Both
  spikes so far learned this the same way: `ci.yml`'s Trivy scan is `scan-ref: .`, the
  whole repository, gating on HIGH and CRITICAL — so throwaway Terraform, which is
  deliberately unencrypted and unrestricted, turns `CI` red and *cannot* be merged.
  That is the gate working. The sequence is: open the pull request, let CI run the
  experiment, read the answer, delete the spike in the same pull request, merge green.
  **Never** add `skip-dirs`, narrow `scan-ref`, or otherwise quiet the scanner to get a
  spike merged — the point of a spike is that it leaves.
- Do not add application code here. It belongs in the app repository.
- Do not weaken a CI security gate to make a build pass. If a finding is genuinely not
  actionable, say so and ask.
