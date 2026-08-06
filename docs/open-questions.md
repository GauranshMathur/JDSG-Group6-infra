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

### Do the four verification questions in `floci.md` have the answers we expect?

Whether the community EKS module applies or forces a hand-rolled config; whether inert-tier
resources really apply; what floci returns on an unimplemented operation; and whether
metadata-only mode covers the CI gate.

**Why it matters:** the first decides how the Terraform is written at all. The third decides
whether a failure is a clean error Terraform can report or something that looks like success —
and a misconfiguration that looks like success is the worst outcome available.

**When:** answered by the first CI run of I-1b, rather than by more reading. A red job is a
faster and more reliable answer than the documentation has given so far.

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
