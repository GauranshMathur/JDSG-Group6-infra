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

### Do the three remaining verification questions in `floci.md` behave as expected?

Whether inert-tier resources really apply; what floci returns on an unimplemented operation;
and whether metadata-only mode covers the CI gate.

**Why it matters:** the second decides whether a failure is a clean error Terraform can report
or something that looks like success — and a misconfiguration that looks like success is the
worst outcome available. It is also the only one of the three that reading a plan cannot
catch.

**When:** answered by the first CI run of I-1b, rather than by more reading. A red job is a
faster and more reliable answer than the documentation has given so far. All three settle on
one apply.

**Note on where this gets answered.** These need floci running, and pulling its image needs a
container registry. Any environment with restricted egress — a sandboxed agent session, a
locked-down runner — will resolve the manifest and then fail on the blob CDN, for Docker Hub
and ECR Public alike. GitHub Actions has no such restriction, which is the other reason the
answers come from CI.

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

### What answers the three remaining questions, given no Terraform may be written yet?

`CLAUDE.md` says no Terraform until I-1a's questions are answered. The roadmap and the entry
above say those answers come from the first CI apply. An apply needs Terraform, so as written
the two rules cannot both be satisfied and I-1b cannot start.

The obvious way out is a **verification spike**: a deliberately minimal, throwaway config —
one inert-tier resource of each kind, plus one deliberately unsupported operation to force the
question-2 case — and a CI job that applies it against floci. It is not the reference design,
it answers all three at once, and it gets deleted afterwards.

**Why it matters:** it is the only thing standing between here and I-1b, and it is a rule
conflict rather than a technical problem, so it will not resolve itself.

**When:** now. Whichever way it goes, one of the two rules needs rewording so the next person
does not hit the same wall.

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
