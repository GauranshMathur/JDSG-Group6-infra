# Architecture

**There will never be a real AWS account.** The enterprise AWS architecture below is the
*reference design* — drawn and documented as a real account would be — and the local stack
is its realization. Terraform is written against the AWS provider so that pointing at real
AWS would be an endpoint change, not a rewrite. Nothing here bills.

![AWS reference architecture](diagrams/aws-reference-architecture.svg)

The source of truth is
[`diagrams/aws-reference-architecture.drawio`](diagrams/aws-reference-architecture.drawio) —
[edit it online in app.diagrams.net](https://app.diagrams.net/#HGauranshMathur%2FJDSG-Group6-infra%2Fmain%2Fdocs%2Fdiagrams%2Faws-reference-architecture.drawio)
and commit back from the editor. A workflow re-renders the SVG on any push to `main` that
changes the `.drawio`, so the picture cannot go stale.

The diagram is the reference design, not an inventory of what the Terraform builds. The one
load-bearing difference: **CloudFront is drawn but not in the Terraform** — it cannot be
applied against the emulator at all (see [decisions.md](decisions.md)).

## One system, one companion artifact

- **The system** is the app running on a local k3d cluster: real PostgreSQL, real object
  storage, Traefik ingress. Load, resiliency and failure testing all happen here.
- **The Terraform** under `infra/terraform/` expresses the reference design and is verified
  in CI against [floci](floci.md), a local AWS emulator. It proves the configuration stands
  up; it never runs the app, because the emulator routes no packets and enforces nothing.

The two describe the same cluster and can drift; keeping the manifests cluster-agnostic
(no EKS-only storage classes, no ALB ingress annotations) is what limits that.

## The reference design, layer by layer

**Edge (global).** DNS at Route 53, CloudFront as the CDN front door over 443, WAF with
managed rule sets, certificates from ACM. CloudFront's origin is the NLB, so nothing behind
the perimeter ever sees the internet directly. Cognito is drawn as the reference sign-in path but is
reference-only — the app owns its authentication in Rails. IAM (roles, IRSA) and KMS
(keys for RDS, S3, EBS) sit at this layer as the global services everything leans on.

**Network.** Three VPCs joined by a Transit Gateway. The perimeter VPC (10.0.0.0/16) holds
everything internet-facing: internet gateway, ALB and NLB, and a NAT gateway and Network
Firewall endpoint per public subnet, one per AZ. The application VPC (10.1.0.0/16) holds
EKS node groups and RDS in private subnets and has no internet gateway — every packet in
or out crosses the transit gateway. NAT carries cluster-started egress only. A DR VPC
(10.2.0.0/16) stands ready over inter-region TGW peering.

**Ingress.** Two load balancer types in series, deliberately. Traffic crosses the internet
gateway and reaches the **NLB** first: the L4 entry point, which gives the perimeter a
fixed-address front door and hands the connection on without inspecting it. The NLB
forwards to the **ALB**, which does the L7 work — host and path routing, TLS from ACM, and
the OIDC sign-in hop against Cognito in the reference design. The ALB is created and kept
in sync by the AWS Load Balancer Controller from the Kubernetes `Ingress`.

Locally neither forwards a packet, since floci emulates both at the API level only. The
NLB's job is the one that survives: k3s's ServiceLB does real L4, and Traefik plays the
ingress controller the ALB stands in for.

**Cluster.** Private subnets, two AZs, an EKS managed node group per zone. Deployment with
replicas ≥ 2, readiness probing `/up`, a PodDisruptionBudget, HPA scaling replicas and the
Cluster Autoscaler scaling nodes, PVCs on the EBS CSI driver for stateful add-ons. Pods
reach RDS on 5432, S3 for media, SSM for secrets via IRSA.

**Reliability and recovery.** Multi-AZ everything; synchronous RDS replication to a
standby; AWS Backup with point-in-time recovery. Across regions, a pilot-light DR region:
S3 cross-region replication and vault copies keep data warm, recovery is an apply plus
restore, Route 53 health-check failover flips DNS.

## What each piece means locally

| Reference (AWS) | Emulator reality | Local move |
| --- | --- | --- |
| CloudFront | Create accepted, read-back crashes the provider | Omitted from the Terraform ([decisions.md](decisions.md)) |
| ALB / NLB, WAF, ACM, Route 53 | Apply cleanly, do nothing | In the Terraform as design; Traefik + k3s ServiceLB do the real ingress |
| VPCs, subnets, security groups, TGW, NAT | Metadata only — nothing routes or filters | In the Terraform as design |
| Network Firewall | Not implemented at all — halts an apply | Commented block with a note |
| EKS + node groups + autoscaler | Real k3s container per cluster; node groups are metadata | CI uses mock mode; scaling demos happen at the k3s/k3d layer |
| RDS Multi-AZ | Real PostgreSQL container, no Multi-AZ or failover | App runs against real PostgreSQL on the cluster; failover demo via an in-cluster operator if wanted |
| S3, ECR, SSM, KMS | Work for real (metadata-level) | Applied and usable |
| CloudWatch | Accepts writes | Prometheus + Grafana in-cluster, when observability lands |
| DR region | No region isolation in the emulator | Reference-only — stays on paper |

## What deploying forces in the app

These are changes to the [app repository](https://github.com/GauranshMathur/JDSG-Group6-app),
made there when they block, recorded here because the deployment is what forces them. The
app was built single-process on purpose; three of its choices break at two replicas:

1. **SQLite → PostgreSQL.** Replicas cannot share a SQLite file. `DATABASE_URL` is already
   the switch, but no CI job has ever run the suite against PostgreSQL.
2. **Per-process cache → shared cache.** The ranked-feed cache and rate limiter live in
   `Rails.cache` memory; two replicas means divergent feeds and a rate limit that counts
   half. Solid Cache vs Redis is in [decisions.md](decisions.md) under Undecided.
3. **Disk → S3 for Active Storage.** Pod filesystems are ephemeral; a redeploy deletes
   every avatar. A `storage.yml` service plus the `aws-sdk-s3` gem.

Also owed: a real readiness endpoint — `/up` returns 200 against a dead database, which is
exactly wrong behind a load balancer.
