# Roadmap

Ordered. Each milestone is a shippable slice; we plan the details of a milestone when we reach
it, not before. **Each milestone is built, tested and merged before the next one starts** — a
milestone is not done until its pull request is green and merged into `main`.

The application's own roadmap is in
[JDSG-Group6-app](https://github.com/GauranshMathur/JDSG-Group6-app). All of its milestones
are complete; nothing here is sequenced against them.

## The premise

**There will never be a real AWS account.** The AWS architecture — EKS, ALB, Multi-AZ RDS, S3,
the full enterprise shape — is the *reference design*, realized entirely locally. Terraform is
written against the AWS provider and applied against
[floci](https://floci.io/floci/), a free local emulator whose EKS emulation runs real k3s
clusters. The design, the local mapping, and what it forces in the app are in
[`infrastructure.md`](infrastructure.md). ElastiCache stays out until Sidekiq exists.

## Two tracks

Decided in [ADR 0001](adr/0001-terraform-verifies-runtime-deploys.md). The Terraform proves the
design stands up, against the emulator; a real local Kubernetes cluster runs the app and is
where load and stress testing happen. **They do not depend on each other**, so after I-1a they
can proceed in either order, or in parallel.

| # | Milestone | Status |
| --- | --- | --- |
| I-1a | Design agreed, reference diagram, and the toolchain questions in [`floci.md`](floci.md) answered | **Done** — design and diagram done; all four questions answered, the last three by a verification spike applying against floci in CI |

### Track A — Terraform, the design verified

Taken first.

| # | Milestone | Status |
| --- | --- | --- |
| I-1b | The full infrastructure pipeline: the reference design written as Terraform, with `fmt` → `validate` → `plan` (saved as an artifact) → `apply` against floci, and state in S3 | Planned |
| I-1c | The pipeline is a required gate: `terraform apply` against a clean emulator must succeed before a pull request merges | Planned |

### Track B — Runtime, the app actually running

| # | Milestone | Status |
| --- | --- | --- |
| I-1d | Local cluster and platform: k3d, Traefik ingress, real PostgreSQL, S3-compatible object storage | Planned |
| I-1e | The app served on it, with the three changes it forces — PostgreSQL, shared cache, S3 media | Planned |
| I-1f | Resiliency demonstrated: HPA, node scaling, drains, zone-loss rescheduling | Planned |
| I-1g | Load testing, latency testing, and the improvement loop they feed | Planned |

## What each milestone leaves behind

**I-1a — the design.** The reference architecture written down and drawn, the emulator's real
depth recorded honestly, the two-track split decided with its costs, and the toolchain
questions answered by measurement.

The EKS module question resolved by reading the module rather than by applying it, because it
turned out to be a question about the module's own defaults: add-ons and access entries — the
blockers we expected — are off, while `encryption_config` and IRSA are on and are what
actually reach unsupported ground. Both are one variable away from being closed, so what is
left is not a compatibility problem but a design choice, still open in
[`open-questions.md`](open-questions.md).

The other three came from CI, as planned, via a throwaway verification spike — and the
answers are better and worse than expected. The inert tier really does apply: VPC, subnets,
security group, ALB, Web ACL, EKS cluster and node group all land in state. EKS mock mode
needs no Docker socket, so the gate can run unprivileged. Unimplemented operations fail
loudly rather than faking success, in two distinct clean shapes, which is what makes an
apply worth gating on.

The worse half: **CloudFront cannot be applied at all** — floci accepts the create and
returns an object that segfaults the AWS provider on read-back — and placement groups are
refused outright. The first contradicts the design's own "apply the inert tier and label
it" rule for the service that rule names, and is now an open question against I-1b. An ALB
also takes a full minute to create, so the gate's duration will be dominated by waiting.
Everything measured is in [`floci.md`](floci.md).

**I-1b — the pipeline.** Terraform for the whole reference design, and the pipeline that
exercises it end to end. The plan is saved with `-out` and published as an artifact, and the
apply applies *that* plan rather than re-planning — the standard separation, so what was
reviewed is what runs.

State goes in S3 on the emulator with `use_lockfile` for native locking. In CI this is
effectively ephemeral, since the bucket dies with the emulator, and that is correct there: the
gate's job is proving the configuration stands up from nothing. The same config against a
persistent local floci is where state genuinely accumulates and incremental applies do what
you would want.

Chicken-and-egg to expect: the state bucket must exist before `terraform init`, and Terraform
is what creates buckets. One bootstrap step with the AWS CLI, before init.

**I-1c — the gate.** Nothing merges without the apply succeeding.

**I-1d to I-1g — the runtime.** A real cluster, the app on it, then resiliency and load. This
is where the three app changes land, and where every figure worth measuring is measured.

## Later, agreed but not designed

- **Flux GitOps** — manifests reconciled from the repository instead of applied by hand.
  Agreed as the direction and explicitly **not on the critical path**.
- **Observability** — Prometheus and Grafana in-cluster, as the CloudWatch stand-in.

## The standing rule

**No real cloud resources, ever.** That half is permanent.

The other half — no Terraform until I-1a's questions are answered — is **discharged**: they
are answered. It is recorded here only because escaping it taught something. As first
written it made I-1b unreachable, since the answers came from an apply and an apply needs
Terraform. The way out was to read the ban as covering Terraform *for the reference design*,
leaving a throwaway verification spike as its one exception: minimal, under `spike/`, gating
nothing, deleted once its answers are recorded. Any future rule of the same shape should say
so up front.
