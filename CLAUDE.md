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

**I-1a — design agreed, toolchain verification outstanding.** The design and the diagram
exist. What remains are the three questions in `docs/floci.md`, all of which need floci
actually running and are expected to be answered by the first CI apply.

The fourth — whether the community EKS module applies against the emulator — is answered,
and answered by reading the module rather than applying it. It resolved into a design choice
instead: the module is two variables from applying (`encryption_config = null`,
`enable_irsa = false`), so the question is whether to accept a cluster that no longer matches
the reference design, or hand-roll. That decision is open in `docs/open-questions.md` and
gets an ADR before I-1b starts.

**The work is two independent tracks — [ADR 0001](docs/adr/0001-terraform-verifies-runtime-deploys.md).**

- **Track A, Terraform (taken first).** The reference design written as Terraform and applied
  against floci. This proves the config stands up; it never runs the app. One root, no
  modules, files split by concern. Terraform stops at AWS — Kubernetes objects stay as
  manifests. `terraform apply` against a clean emulator is a CI gate.
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
  against floci and then does nothing — the whole network, both load balancers, CloudFront,
  WAF. Apply them so the Terraform matches the diagram, and mark them so nobody reads a Web
  ACL in the state file as something that filters traffic.
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
- Do not write Terraform until I-1a's toolchain questions in `docs/floci.md` are answered.
- Do not add application code here. It belongs in the app repository.
- Do not weaken a CI security gate to make a build pass. If a finding is genuinely not
  actionable, say so and ask.
