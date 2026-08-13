# Open questions

Decisions not yet taken. This is a **live list** — when work answers a question, it is deleted
from here and the answer moves into whichever document it belongs to. It is not a log of
things we once wondered about.

Each entry says what the question is, why it matters, and when it needs answering. A question
with no "when" tends to sit here forever; a question with one becomes a decision on time.

Answered decisions live in [`adr/`](adr/) when the trade-off is worth remembering, or in the
relevant document when it is not.

---

## The premise, already answered

The earlier questions about an AWS account, a budget and a domain name are answered by the
premise: there will never be a real account, so nothing bills and TLS terminates against a
local hostname.

Whether floci's emulation is deep enough is no longer load-bearing either.
[ADR 0001](adr/0001-terraform-verifies-runtime-deploys.md) splits the work in two — floci
verifies that the Terraform stands up, and a real local Kubernetes cluster runs the app — so
emulation depth only has to be good enough to apply resources, not to serve traffic. Also
settled there: no Terraform modules, Terraform stops at AWS with Kubernetes objects as
manifests, and images come from GHCR rather than the emulated ECR.

---

## Track A — Terraform

### Community EKS module with overrides, or hand-rolled?

`floci.md` now records what the module actually does at defaults: the add-ons and access
entries we expected to block it are off, and what blocks it instead is `encryption_config`
(defaulting to `{}`, which is not `null`, so the gate opens) and IRSA's `tls_certificate`
data source making a real outbound TLS handshake. Both are one variable each —
`encryption_config = null`, `enable_irsa = false`.

So this is no longer "does it work". It is a choice between two configurations that are both
achievable:

- **The module, with floci-specific overrides.** Least Terraform written, and it inherits the
  module's IAM, security-group and node-group scaffolding. The cost is that the applied
  cluster is no longer the cluster the reference design describes — secrets encryption and
  IRSA are exactly the kind of production shape the design is meant to demonstrate, and
  turning them off to satisfy the emulator inverts the relationship. It also drags in a
  nested registry module (`terraform-aws-modules/kms/aws`), against the one-root-no-modules
  rule.
- **Hand-rolled.** More Terraform, and none of it inherited. But the resources applied are
  exactly the resources chosen, the emulator's gaps are visible in the config rather than
  hidden behind a variable, and the inert tier gets labelled the way `CLAUDE.md` requires.

**Why it matters:** it decides how every Terraform file in I-1b is written, and it is the
kind of choice that is expensive to reverse once the whole design is expressed one way.

**When:** before I-1b starts. It has a real alternative and a real cost either way, so it
gets an ADR rather than a line in a document.

### What does the reference design do about CloudFront, which cannot be applied?

Raised by the verification spike, which found that floci accepts `CreateDistribution` and
then returns an object incomplete enough to **segfault the AWS provider** reading it back.
CloudFront is not inert-but-appliable; it cannot be applied at all. Measured, with the
stack trace, in [`floci.md`](floci.md).

**Why it matters:** `CLAUDE.md` says inert resources are applied and labelled, and names
CloudFront as an example. That instruction is now impossible to follow for the one service
it names. CloudFront is also the front door of the reference design — the edge chain in
[`infrastructure.md`](infrastructure.md) starts there — so leaving it out means the
Terraform no longer matches the diagram, which is the thing "apply them and label them"
exists to guarantee.

**It is narrower than "CloudFront cannot exist in the Terraform", though.** The spike's
plan output included `aws_cloudfront_distribution` in all thirteen resources: **`fmt`,
`validate` and `plan` all handle it fine, and only `apply` crashes.** So the resource can
stay in the configuration and appear, fully specified, in the plan artifact this
pipeline already publishes (I-2.5). What is unreachable is *state*, and a CloudFront
entry in the state of an emulator that does not serve traffic was never worth much. The
question is really "how does `apply` stay green while the design keeps its front door".

**The options:**

- **Omit it, and say so.** The Terraform stops at the ALB; the diagram keeps CloudFront
  with a marker saying it is undeployable against the emulator. Honest, and it breaks the
  Terraform-matches-diagram property the rule was written to protect.
- **Keep it behind a `count = var.emulated ? 0 : 1`.** The resource stays in the
  configuration and reads as part of the design, and applies against real AWS. Costs a
  conditional the one-root-no-modules style has so far avoided, and a variable whose only
  purpose is to describe the emulator's shortcomings. Note it also removes the resource
  from the *plan* when emulated, which is the visibility the point above was buying — so
  pair it with a documentation-only `plan` at `emulated = false` if the published plan is
  meant to show the whole design. That is a second plan that is never applied, which cuts
  against [`ci-cd.md`](ci-cd.md)'s "apply the plan you published" rule and so must be
  labelled unmistakably, or it becomes the exact confusion that rule prevents.
- ~~**Pin an older AWS provider.**~~ **Eliminated by measurement.** A matrix applying one
  distribution against floci on `4.67.0`, `5.0.0`, `5.31.0`, `5.70.0`, `6.0.0` and
  `6.59.0` crashed on **every single version**, identically — the same nil pointer in the
  CloudFront read-back, across two major versions and three years of releases. This is not
  a regression in a recent provider; it is what the whole family does with a response
  shaped like floci's. Recorded in [`floci.md`](floci.md).
- **Report it upstream.** floci is MIT-licensed and the response is genuinely incomplete;
  the provider crashing on it is arguably also a provider bug. Fixes nothing this
  milestone, and is the only option that stops the next person hitting it.

**What does not work, checked rather than assumed:** there is no `-exclude` flag to drop a
single resource from an apply — it does not exist in Terraform 1.13 or 1.15, only
`-target`, and targeting everything-but-one is precisely the usage Terraform warns is for
exceptional recovery, not pipelines.

**When:** before I-1b writes the edge layer. The cheap escape has been tried and does not
exist, so this is now a choice between the three remaining options rather than a question
with a possible technical answer. `count = var.emulated ? 0 : 1` is the least-bad of them
unless the published plan's completeness matters more than the apply's.

### Does the state bucket bootstrap cleanly?

State goes in S3 on the emulator, but the bucket must exist before `terraform init` and
Terraform is what creates buckets.

**Why it matters:** it is the one ordering problem in the pipeline, and getting it wrong makes
the first run of every fresh emulator fail in a way that looks like a Terraform bug.

**When:** I-1b, with the backend.

---

## Track B — Runtime

### Which local Kubernetes distribution?

[ADR 0001](adr/0001-terraform-verifies-runtime-deploys.md) names k3d as the likely choice — it
is k3s in Docker, so it matches what floci's EKS emulation would have launched anyway, and it
ships Traefik and ServiceLB. kind and minikube are the alternatives.

**Why it matters:** it decides what the manifests are exercised against, and how node scaling
and zone-loss rescheduling get demonstrated in I-1f.

**When:** at the start of track B (I-1d). Nothing before then depends on it.

### What provides S3-compatible storage?

MinIO is the obvious candidate. Active Storage needs an S3-compatible endpoint, and the
`aws-sdk-s3` gem plus a `storage.yml` service is the app-side change either way.

**Why it matters:** it is one of the three app changes deploying forces, and the one with no
local default the way PostgreSQL has.

**When:** I-1e, when the app first needs somewhere to put an avatar that survives a redeploy.

### Shared cache: Solid Cache or Redis?

The app's ranked-feed cache and rate limiter are per-process memory, which breaks at two
replicas. Solid Cache rides on PostgreSQL and adds no service; Redis is the conventional
answer and will be wanted for Sidekiq eventually anyway.

**Why it matters:** picking Solid Cache now and Redis later means doing the work twice; picking
Redis now adds a service before anything needs it. **This is an app-repository change**, but
the decision is forced here, by replica count.

**When:** the moment the deployment scales past one replica — I-1e or I-1f.

### What tooling for load and latency testing?

k6 and Toxiproxy are the leading candidates, deliberately undecided.

**Why it matters:** it decides what the numbers mean and whether they are reproducible.

**When:** I-1g. Nothing before it depends on the choice.

---

## Delivery

### Required status checks

`main` has none, so nothing gates a merge and auto-merge cannot arm.

**Why it matters:** two branches can each pass in isolation and still break once merged.

**When:** with I-1b, when the pipeline has something worth requiring. Requiring checks against
a pipeline that only validates Compose files would be ceremony.

### Should this repository cut releases?

The app repository derives a version from Conventional Commits and publishes an image. There
is no equivalent artifact here — Terraform and manifests are applied, not published.

**Why it matters:** tagging infrastructure gives you something to roll back *to*, which matters
once anything real depends on it. Today nothing does.

**When:** not urgent. Worth deciding before track B produces a cluster anyone else uses.
