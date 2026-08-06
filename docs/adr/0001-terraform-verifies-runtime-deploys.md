# ADR 0001 — Terraform is verified against the emulator; the app is deployed on a real local cluster

**Status:** Accepted
**Date:** 2026-08-05
**Milestone:** I-1a

## Context

The reference design is an enterprise AWS architecture realized entirely locally, with
[floci](https://floci.io/floci/) as the AWS emulator. The original sequencing put both jobs
on one track: I-1b stands the platform up with Terraform against floci, I-1c serves the app
on what that produced.

Researching how deep floci's emulation actually goes changed the picture. It implements
services in two meaningfully different ways:

- **Real Docker** — EKS launches an actual k3s container, RDS an actual PostgreSQL,
  ElastiCache an actual Redis. The app would talk to real engines.
- **In-process** — everything else, including the entire network (VPCs, subnets, security
  groups, NAT gateways) and both load balancer types. These answer the API and store state;
  they route no packets and enforce nothing.

Two things follow. First, three of I-1a's five verification items exist only because the app
was going to run on emulated services: whether Rails connects happily through the RDS auth
proxy under migration load, whether Active Storage works against floci's S3, and whether
IRSA-style scoping does anything. Each is a potential blocker that would be discovered late —
after the Terraform had been written around it.

Second, the emulator's ceiling is proving *wiring*. It has no quotas, no throttling, no
realistic failure modes, no packet filtering. Load and latency figures measured against it
would describe the emulator, not the app.

## Decision

**Two tracks, independent of each other.**

| | Terraform + floci | Local Kubernetes + manifests |
| --- | --- | --- |
| Purpose | Prove the infrastructure-as-code stands up | Actually run the app |
| Proves | The resource graph is coherent, dependencies resolve, computed attributes flow, nothing reaches an API that does not exist | The app serves; load, stress and latency behaviour |
| Runs the app | Never | Yes |
| Backing services | Emulated, metadata-shaped | Real PostgreSQL, real object storage, real ingress |
| Where it runs | CI, on any pull request touching `infra/` | Locally, on demand |

The Terraform track can run in floci's metadata-only mode (`FLOCI_SERVICES_EKS_MOCK=true`),
which needs no Docker socket and starts in milliseconds — so "`terraform apply` must succeed
against a clean emulator" becomes a CI gate rather than something someone ran once.

Alongside this, settled in the same discussion:

- **No modules.** One root, files split by concern. Modules earn their keep when the same
  shape is instantiated more than once; there is one of everything here, and floci has no
  region isolation, so even the DR region never becomes a second instantiation.
- **Terraform stops at AWS.** Kubernetes objects stay as manifests, later reconciled by Flux.
  Pulling them into Terraform forces two-phase applies, because the Kubernetes provider
  cannot plan against a cluster that does not exist yet.
- **Images come from GHCR**, which the release workflow already publishes to.
- **Inert resources are still applied, and labelled.** The load balancers, the edge chain and
  the whole network create cleanly and do nothing; they carry a marker saying so.

## Consequences

**Good**

- The risk that could actually sink the milestone is gone. If floci's RDS proxy or its S3 is
  too shallow, nothing is blocked, because the app never touches either.
- Terraform verification becomes a CI gate — cheap, fast, and run on every change.
- Each tool does the job it is good at. floci proves control-plane wiring; a real local
  cluster proves runtime.
- The three app changes this milestone forces — PostgreSQL, shared cache, S3 media — get
  proven against real services rather than an emulator's approximation of them.

**Bad, or at least accepted**

- **Two things that can drift.** Nothing forces the cluster the Terraform describes to match
  the cluster the manifests land on. The mitigation — keep manifests cluster-agnostic, so no
  EKS-specific storage classes and no ALB ingress annotations — is a rule someone has to
  follow, not a mechanism that enforces itself.
- **The bar for the Terraform drops to "it applied."** Since floci enforces no security group
  and routes no packet, a successful apply proves the configuration is well-formed, not that
  the design would work. Nothing available locally can prove the latter; the honest move is
  to say so rather than let the green check imply more.
- **There is no single "`terraform apply` and the app is live" demonstration.** The story
  becomes two stories, which is less satisfying to show than one.
- **floci's real-Docker tier goes mostly unused** — and that tier was the reason floci was
  chosen over alternatives in the first place. The emulator is now being used for the shallow
  thing every emulator does well.

## Alternatives

**One track, the app runs on floci's EKS.** The original plan. Rejected because it bets the
milestone on emulation depth the documentation does not establish, and the failure mode is
finding out late — after the Terraform has been shaped around it.

**No emulator at all; `validate` and `plan` only.** Cheaper still, and needs no Docker.
Rejected because `apply` exercises dependency ordering and computed attributes flowing
between resources, and `plan` on resources that do not yet exist makes no API calls at all.
The gap between "plans" and "applies" is where most infrastructure-as-code bugs live.

**Deploy on floci's EKS but run the load tests elsewhere.** The worst of both: still bets on
the emulation for the deployment, and still maintains two stacks.

## Revisiting

If I-1a finds floci's real-Docker tier deeper than assumed, the tracks could merge. Note the
asymmetry that makes splitting now the safer order: merging later is cheap, while splitting
later is not, because by then the Terraform would have been written around the emulator's
shape rather than the reference design's.
