# Infrastructure

**Status: design direction agreed, details in discussion.** This replaces the earlier
Fargate proposal, which assumed a real AWS account. The premise changed:

**There will never be a real AWS account.** This project practices enterprise-grade system
design, built and exercised entirely locally. The AWS architecture below is the *reference
design* — drawn, documented and diagrammed as a real AWS account would be — and the local
stack is its faithful realization. Terraform is written against the AWS provider so that
pointing at real AWS would be a provider/endpoint change, not a rewrite. Nothing real is
ever billed; local clusters and emulators are free to create and destroy.

The architecture diagram (draw.io, official AWS icon set) shows the full enterprise
deployment: the edge chain (Route 53, CloudFront, WAF, ACM), both load balancer types,
ingress and egress paths, the Kubernetes objects inside the cluster, two availability
zones, encryption and identity (KMS, IAM/IRSA), and the backup and DR-region story.

![AWS reference architecture](diagrams/aws-reference-architecture.svg)

The source of truth is
[`diagrams/aws-reference-architecture.drawio`](diagrams/aws-reference-architecture.drawio).
**Open it online, straight from this repository:**
[edit in app.diagrams.net](https://app.diagrams.net/#HGauranshMathur%2FJDSG-Group6-infra%2Fmain%2Fdocs%2Fdiagrams%2Faws-reference-architecture.drawio)
— authorize GitHub when prompted and edits can be committed back to the repo from the
editor. The SVG above is not exported by hand: the `render-diagrams` workflow re-renders
it on every push to `main` that changes the `.drawio`, so the picture follows the source
(see [`ci-cd.md`](ci-cd.md)).

## Two tracks, not one

**Decided in [ADR 0001](adr/0001-terraform-verifies-runtime-deploys.md).** The Terraform and
the running app are separate exercises that do not depend on each other:

| | Terraform + floci | Local Kubernetes + manifests |
| --- | --- | --- |
| Purpose | Prove the infrastructure-as-code stands up | Actually run the app |
| Proves | The resource graph is coherent, dependencies resolve, nothing reaches a missing API | The app serves; load, stress and latency behaviour |
| Runs the app | Never | Yes |
| Backing services | Emulated, metadata-shaped | Real PostgreSQL, real object storage, real ingress |
| Where it runs | CI, on any pull request touching `infra/` | Locally, on demand |

The reason is that floci's emulation is two-tiered — a handful of services run real engines
in Docker, and everything else answers the API while doing nothing. Betting the deployment
on the first tier being deep enough is the risk this split removes. It costs a single
"`terraform apply` and the app is live" demonstration, and it leaves two descriptions of the
cluster that can drift; the mitigation is keeping the manifests cluster-agnostic. The full
reasoning and the costs are in the ADR.

Shape of the Terraform, settled at the same time:

- **No modules.** One root, files split by concern. There is one of everything, and floci
  has no region isolation, so even the DR region never becomes a second instantiation.
- **Terraform stops at AWS.** Kubernetes objects stay as manifests, later reconciled by
  Flux — the Kubernetes provider cannot plan against a cluster that does not exist yet.
- **Images come from GHCR**, which the release workflow already publishes to. This gives up
  floci's automatic ECR-to-k3s `registries.yaml` wiring, so the cluster needs working egress
  and a pull secret if the package is not public.
- **Inert resources are applied and labelled**, so the Terraform matches the diagram without
  anyone mistaking a Web ACL in the state file for something that filters.

## Toolchain

| Piece | Tool | Note |
| --- | --- | --- |
| Provisioning | Terraform (v1.10+), AWS provider | Applied against floci's endpoint (`http://localhost:4566`), not real AWS — moving to real AWS would be a provider endpoint change |
| AWS emulation | [floci](https://floci.io/floci/) | Free, MIT-licensed local AWS emulator: 69 services including EKS, RDS, S3, ECR, Route 53, SSM, ElastiCache. One container, one port, no feature gates. LocalStack-compatible endpoint. **How it works and how deep each emulation goes: [`floci.md`](floci.md)** |
| Kubernetes | k3s — launched *by* floci's EKS emulation | floci's EKS runs real k3s clusters in Docker (`rancher/k3s`) with a live Kubernetes API server, so `terraform apply` on an EKS cluster yields an actual cluster to `kubectl` into. Node add/remove is a container operation, which is what makes autoscaling demonstrable locally |
| GitOps | Flux | Agreed as the direction but explicitly **not on the critical path** — nice to add once the platform stands, not a blocker for anything |
| Images | GHCR (already published on every release) | The reference design says ECR; floci emulates ECR, and the cluster can also pull the GHCR images that already exist — I-1a decides which |

**Recorded constraints, honestly:**

- floci's "real Docker" services — EKS included — need Docker socket access on the host.
- An emulator proves *wiring*: that the Terraform is coherent and the app runs on what it
  stands up. It does not prove AWS behaviour — quotas, IAM edge cases, managed-service
  failure modes stay unproven. Accepted by design, since nothing will ever run on real AWS.
- If any service's emulation turns out too shallow in practice, the fallback holds: plain
  k3d plus the same Kubernetes manifests, with the Terraform for that piece proven by
  `plan`. I-1a's verification decides service by service.
- Three gaps are already known from floci's own docs and change how parts of this design
  are realized locally — **no ALB emulation** (Traefik in k3s plays its part), **node
  groups are API metadata** (node-scaling demos happen at the k3s layer), and **no RDS
  Multi-AZ/failover** (single Postgres, with an in-cluster operator if the failover
  demonstration is wanted). Detail and the full can/can't list: [`floci.md`](floci.md).

## The reference architecture

What the diagram shows, in words — five layers:

**Edge (global).** Users resolve DNS at Route 53 and hit **CloudFront** (the CDN) over 443,
with **WAF** attached (managed rule sets) and the certificate from **ACM**. CloudFront's
origin is the ALB — so the ALB is the only ingress into the perimeter VPC, and it never
sees the internet directly. **IAM** (roles, IRSA for pods) and **KMS** (encryption keys for
RDS, S3 and EBS) sit at this layer too, since they are global services everything else
leans on.

**Network topology.** Three VPCs, each with its own /16, connected by a **Transit
Gateway** whose attachment ENIs are drawn where they sit. The **perimeter VPC**
(10.0.0.0/16) holds everything that faces the internet: the internet gateway, the ALB and
NLB behind their security group, and a NAT gateway and Network Firewall endpoint per
public subnet (10.0.0.0/20 and 10.0.16.0/20, one per AZ). The **application VPC**
(10.1.0.0/16) holds the EKS node groups and RDS in private subnets (10.1.0.0/20 and
10.1.16.0/20) and has no internet gateway at all — every packet in or out crosses the
transit gateway to the perimeter. A **DR VPC** (10.2.0.0/16) stands ready in the DR
region, reached over inter-region TGW peering. Security groups are drawn where they wrap:
the load balancers, each zone's nodes, and the database pair.

**Ingress into the cluster.** Two load balancer types, deliberately: the **ALB** is the L7
path — created and kept in sync by the AWS Load Balancer Controller *from* the Kubernetes
`Ingress` resource, TLS from ACM — and an **NLB** is the L4 path (TLS passthrough,
non-HTTP), which fronts the in-cluster ingress controller. The local realization uses the
NLB-shaped path: Traefik in k3s plays the ingress controller. floci emulates both load
balancers at the API level, so both appear in the Terraform, but neither forwards a packet
— see [`floci.md`](floci.md). The NLB's job is the one that survives locally, because k3s's
ServiceLB does real L4.

**Inside the cluster** (private subnets, two AZs, an EKS managed node group per zone):
each zone's EC2 node box carries the basic Kubernetes objects that run the app —
`Ingress`, `Deployment`, `Pod`, `Service`, `PVC` — drawn with the community icons as a
deliberately unwired list: what lives on a node, not how it connects. Arrows on the
diagram mean traffic, so both load balancer paths land on the node boxes, and the wiring
between the objects waits for the dedicated in-cluster dataflow diagram, along with what
it will detail: the `Deployment`'s replicas ≥ 2 with readiness probing `/up` and a
PodDisruptionBudget, the **HPA** scaling replicas, the **Cluster Autoscaler** scaling
node groups, and the **PVC** on the EBS CSI driver (gp3) for stateful add-ons like
Prometheus. Pods reach RDS on 5432, S3 for media, and SSM for secrets via IRSA; nodes
pull images from ECR; egress leaves the application VPC over the transit gateway, then
runs NAT gateway → **Network Firewall** (egress inspection) → internet gateway in the
perimeter VPC, per AZ — the same internet gateway ingress enters through, the perimeter's
one door in either direction. Security groups scope every hop; nothing in a private
subnet is internet-reachable.

**Reliability and recovery.** Within the region: Multi-AZ everything, synchronous RDS
replication to the standby, and **AWS Backup** running RDS and EBS plans with
point-in-time recovery into a vault. Across regions: a **DR region in pilot-light shape** —
no compute runs there; S3 cross-region replication and cross-region backup-vault copies
keep the data warm, and recovery is `terraform apply` into the DR region, restore RDS from
the copied snapshots, point Active Storage at the replica bucket, and Route 53
health-check failover flips DNS. RTO is the apply-plus-restore time; RPO is the
replication/snapshot lag.

Resiliency, and how each piece is demonstrated locally:

| Reference (AWS) | What it survives | Local demonstration |
| --- | --- | --- |
| Two AZs everywhere | Loss of a data centre | Two k3s node groups labelled as zones; delete one and watch rescheduling |
| EKS node groups + cluster autoscaler | Node loss; load growth | Join/remove k3s agent containers (node groups are metadata in floci — see [`floci.md`](floci.md)); HPA scales pods, node count follows |
| ≥2 web replicas + PodDisruptionBudget | Deploys and drains without downtime | Rolling deploy under load; `kubectl drain` |
| RDS Multi-AZ (primary + standby) | Database instance loss | Postgres in-cluster with an operator (e.g. CloudNativePG) failing over — floci's RDS has no Multi-AZ, so the failover demo runs in-cluster |
| ALB/NLB health checks → pod readiness | Routing to a dead pod | Traefik + readiness probes against the app's `/up` |
| AWS Backup + PITR | Bad deploy, data corruption | Postgres dump/restore exercised against the local database |
| DR region (pilot light): S3 CRR, vault copies, Route 53 failover | Loss of a region | **Reference-only.** Demonstrated on the diagram and in words — at most a second floci endpoint. The one layer that stays paper |

## What this forces in the app — read before deploying

**These are changes to the [app repository](https://github.com/GauranshMathur/JDSG-Group6-app),
not to this one.** They are recorded here because this is the milestone that forces them, and
because nothing in the app's own roadmap would otherwise explain why they are needed.

The app was built single-process on purpose, and three of its choices break the moment a
second replica exists. **This is expected.** Finding these under load is part of the point;
they are recorded here so they read as a plan rather than a surprise:

1. **SQLite → PostgreSQL.** Replicas cannot share a SQLite file. The switch is
   `DATABASE_URL` by design but has never been proven — no CI job has ever run the suite
   against PostgreSQL. The job belongs in the [app repository](https://github.com/GauranshMathur/JDSG-Group6-app)
   and lands with this milestone.
2. **Per-process cache → shared cache.** The ranked-feed cache and the sign-in rate limiter
   live in `Rails.cache` memory. Two replicas means two divergent feeds and a rate limit
   that counts half. Fix is Solid Cache (on Postgres, no new service) or Redis — decided
   when replicas go past one, recorded in `open-questions.md`.
3. **Disk → S3 for Active Storage.** Pod filesystems are ephemeral; a redeploy deletes
   every avatar. Locally this targets the emulator's S3 (or MinIO); the code change is a
   `storage.yml` service plus the `aws-sdk-s3` gem.

Also owed to this milestone: a real readiness endpoint — `/up` returns 200 against a dead
database, which is exactly wrong for a load balancer. An app-repository change, forced by
putting the app behind one.

## Later phases (agreed, not yet designed)

- **Load testing and latency testing** — how the app behaves as users grow, what breaks
  first, and whether the fix is infra or app. Tooling deliberately undecided (k6 and
  Toxiproxy are the leading candidates; the app repository's `docs/latency.md` already
  sketches the questions).
  This phase starts once the app is serving on the local platform.
- **Flux GitOps** — manifests reconciled from the repo instead of applied by hand.
- **Observability** — Prometheus + Grafana in-cluster as the CloudWatch stand-in.

## Sequencing

Track A is taken first, but after I-1a the two tracks do not depend on each other.

| Step | Track | What exists at the end |
| --- | --- | --- |
| I-1a | — | This design agreed; the reference diagram; the remaining toolchain questions in [`floci.md`](floci.md) answered |
| I-1b | A | The reference design written as Terraform: VPC, EKS, RDS, S3, ECR, IAM, SSM and the edge chain. One root, no modules |
| I-1c | A | `terraform apply` against a clean floci succeeds, and is a CI gate on any pull request touching `infra/` |
| I-1d | B | Local cluster and platform: k3d, Traefik ingress, real PostgreSQL, S3-compatible object storage |
| I-1e | B | The app served on it: image pulled, migrations run, `/up` green behind ingress — with the three app changes above made as they block |
| I-1f | B | Resiliency demonstrated: HPA, node scaling, drains, zone-loss rescheduling |
| I-1g | B | Load and latency testing, and the improvement loop it feeds |

The standing rule adapts rather than dies: **no real cloud resources, ever** — and no
Terraform until I-1a's design is agreed and the toolchain questions are answered.
