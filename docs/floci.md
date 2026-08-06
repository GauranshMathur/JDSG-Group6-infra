# floci — the local AWS emulator

What [floci](https://floci.io/floci/) is, how it works, how far its emulation goes, and —
the part that matters here — what that means for realizing our
[reference architecture](infrastructure.md) locally. Researched from the project's
[README](https://github.com/floci-io/floci), its service docs (EKS, EC2, RDS), and the
[CLI repo](https://github.com/floci-io/floci-cli); anything the docs left unclear is listed
at the end as an I-1a verification item rather than assumed.

## What it is

A free, MIT-licensed family of local cloud emulators (AWS, Azure, GCP, OCI — one container
per cloud). The AWS emulator speaks the AWS APIs on a single endpoint, `localhost:4566`,
so the AWS SDK, CLI, Terraform (v1.10+), OpenTofu and CDK all work by pointing at that
endpoint — validated upstream by ~2,500 automated compatibility tests. No auth token, no
paid tier, no feature gates, no telemetry. It exists in part because LocalStack's community
edition was sunset in March 2026; floci is a drop-in replacement (same default port, its
LocalStack environment variables auto-translate).

Built as a Quarkus Native binary: ~90 MB image, ~24 ms startup, ~13 MiB idle — the
emulator itself costs effectively nothing next to the containers it manages.

## How it works

Services are implemented in one of three ways, and knowing which is which is most of
knowing what floci can and cannot do:

| Tier | How | Services (examples) |
| --- | --- | --- |
| Stateless, in-process | Java implementations answering the API directly | IAM, STS, SSM, Secrets Manager, KMS, SQS, SNS, Route 53, CloudWatch, CloudFormation |
| Stateful, in-process | Same, plus a pluggable storage backend | S3, DynamoDB |
| **Real Docker** | floci launches *actual containers* running real engines | EKS (k3s), RDS (real PostgreSQL/MySQL/MariaDB), ElastiCache (real Redis), EC2 (a container per instance), Lambda, ECS, OpenSearch, MSK |

The real-Docker tier is the honest kind of emulation — your app talks to a real PostgreSQL
16, a real Redis, a real Kubernetes API server — and it is why floci needs the Docker
socket mounted (`-v /var/run/docker.sock`). A few services are **stubs** that return
shaped dummy data: Textract, Transcribe, Bedrock Runtime.

State: four storage modes via `FLOCI_STORAGE_MODE` — `memory` (ephemeral, fastest),
`persistent` (write-through to disk), `hybrid` (memory with async 5-second flush), `wal`
(write-ahead log). Multi-account isolation works by using different 12-digit access key
IDs; the default account is `000000000000`.

Running it, via the CLI (`floci start`, `floci env`, `floci doctor`, snapshots,
`--persist`) or plain compose:

```yaml
services:
  floci:
    image: floci/floci:latest          # latest-compat adds AWS CLI + boto3 inside
    ports: ["4566:4566"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
```

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
```

## EKS, specifically — since it is our core

- `CreateCluster` (default, "real mode") launches **one k3s container per cluster**
  (`rancher/k3s:latest`, overridable), its API server published on a host port from
  6500–6599. The cluster goes `ACTIVE` once k3s answers `/readyz`.
- `aws eks update-kubeconfig --name <cluster>` then `kubectl get nodes` **works
  end-to-end**: floci wires a TokenReview webhook into k3s that maps the AWS-style token to
  `system:masters`, so no `aws-iam-authenticator` is needed.
- **ECR integration is built in**: each k3s container gets a generated `registries.yaml`
  mirroring floci's ECR, so images pushed to the emulated ECR are pullable by pods without
  manual configuration.
- Node group and Fargate profile APIs exist (create/describe/list/delete, 23 operations
  total), **but node groups appear to be metadata** — the docs do not say they launch
  additional worker containers, and there is no `UpdateNodegroupConfig`. The cluster's
  capacity is the one k3s container.
- A `FLOCI_SERVICES_EKS_MOCK=true` mode stores metadata only — useful for cheap
  Terraform-plan-level tests.
- Not supported: cluster config/version updates, add-ons, identity provider configs,
  access entries, encryption config.

### What the community EKS module does at defaults — and it is not what we expected

Verified by reading `terraform-aws-modules/eks` **v21.24.1** rather than by applying it —
the emulator is not needed to find out which resources a module declares and which of them
its defaults actually instantiate.

The expectation recorded here was that add-ons and access entries would be the blockers.
They are not: **all four of the unsupported EKS resource types are off at defaults.**

| Module resource | Gate | Default | Instantiated? |
| --- | --- | --- | --- |
| `aws_eks_addon` (×2) | `var.addons != null` | `null` | No |
| `aws_eks_identity_provider_config` | `var.identity_providers != null` | `null` | No |
| `aws_eks_access_entry` | `local.merged_access_entries` | `access_entries = {}`, `enable_cluster_creator_admin_permissions = false` | No |
| `aws_eks_access_policy_association` | `local.flattened_access_entries` | — | No |

Two things the module does do by default are the real obstacles:

- **Encryption config is on.** `var.encryption_config` defaults to `{}`, and the gate is
  `local.enable_encryption_config = var.encryption_config != null`. An empty object is not
  null, so the gate opens: the cluster gets a `dynamic "encryption_config"` block with
  `resources = ["secrets"]`, and `create_kms_key` (default `true`) provisions a KMS key to
  fill it. Every `CreateCluster` therefore carries an `encryptionConfig` — the one item on
  the unsupported list that is reached without asking for it. Setting
  `encryption_config = null` closes it.
- **IRSA does real network I/O.** `enable_irsa` and `include_oidc_root_ca_thumbprint` both
  default to `true`, which instantiates `data "tls_certificate" "this"` against
  `aws_eks_cluster.this[0].identity[0].oidc[0].issuer` and makes a genuine outbound TLS
  handshake to read a thumbprint. This fails on whatever floci returns for the issuer —
  absent, or synthetic and undialable — and it fails for a reason that has nothing to do
  with EKS API coverage. `enable_irsa = false` closes it.

So the module is not categorically incompatible; it is two variables away from applying.
That turns the question from a compatibility one into a **design** one — a cluster
configured `encryption_config = null, enable_irsa = false` is no longer the cluster the
reference design describes, which is most of the reason for writing the Terraform against
the AWS provider at all. Recorded as an open decision in
[`open-questions.md`](open-questions.md).

Two smaller findings, worth having before the choice is made:

- The module pulls a **nested registry module**, `terraform-aws-modules/kms/aws` v4.0.0, to
  create that key. Adopting it means adopting a module tree, which sits badly with the
  one-root-no-modules rule in `CLAUDE.md`.
- Managed node groups are a submodule declaring `aws_eks_node_group` alongside an
  `aws_launch_template` and an `aws_placement_group`. Since floci's node groups are metadata
  and its EC2 tier is per-instance containers, whether those two apply is unknown and is
  folded into question 1 below.

Only one of the two obstacles is an EKS coverage gap at all. Encryption config is on floci's
unsupported list; the IRSA one is a `tls_certificate` data source reaching the network, which
would behave the same way against any endpoint that does not serve a real OIDC issuer. Worth
separating, because only the first would be fixed by floci implementing more of the EKS API.

## How it differs from real AWS

The differences cluster into two kinds.

**Fundamental to being an emulator** — these hold for any local emulation and are the
accepted cost of never having a real account:

- **The network is not real.** VPCs, subnets, security groups, NAT and internet gateways
  are stored as metadata — Terraform creates and reads them happily, but nothing enforces
  them. There is no packet filtering; Docker bridge networking does the actual routing.
- **No region isolation** — every region name points at the same emulator; no cross-region
  replication.
- **No quotas, throttling, or realistic failure modes.** The emulator never rate-limits
  you, never runs out of capacity, and its IAM does not exercise the sharp edges real IAM
  has. Billing-shaped APIs return synthetic data.
- Proving *wiring* is therefore the ceiling: that the Terraform is coherent, the services
  connect, the app runs. AWS *behaviour* — what fails, when, and how — stays unproven.

**Specific gaps that touch our design** — found in the service docs, each with the move it
forces:

| Reference design piece | floci reality | Our move |
| --- | --- | --- |
| **ALB as the only ingress** | Emulated, but **in-process**: `aws_lb` creates, describes and returns a DNS name; nothing forwards a packet | Ingress runs at the Kubernetes layer instead: k3s ships Traefik + ServiceLB. The ALB stays in the reference diagram *and in the Terraform*; locally, Traefik plays its part |
| **NLB** as the L4 path | Same tier as the ALB — API only | This is the half that survives: k3s's ServiceLB (klipper-lb) does real L4, so a `Service` of type `LoadBalancer` genuinely gets a host port. The NLB's *job* is realized locally; it is just realized by k3s, not by floci |
| EKS **managed node groups** ×2 AZs, cluster autoscaler | Node groups are API metadata; one k3s container is the cluster; no ASG integration | Multi-node and node-scaling demos happen at the k3s layer — joining/removing k3s agent containers — not through the EKS API. Zone labels are ours to fake |
| **RDS Multi-AZ** primary + standby | Real PostgreSQL 16 container behind an auth proxy (ports 7000–7099) — but no Multi-AZ, failover, or read replicas | Not used at all under [ADR 0001](adr/0001-terraform-verifies-runtime-deploys.md): the app runs against a real PostgreSQL on the local cluster, not against floci's. The RDS resources stay in the Terraform as design |
| ACM certificate on the ALB | ACM is emulated (issuance and validation lifecycle), and so is the ALB — but attaching one to the other changes nothing observable | TLS terminates at Traefik with a locally-issued cert, or is accepted as HTTP locally |
| **Network Firewall** for egress inspection | **Not among the 69 services** — this one genuinely does not exist | The only resource that cannot be applied. Stays as a commented block with a note, so the Terraform still records the design |
| CloudWatch dashboards/alarms | Logs/metrics APIs accept writes | Real observability, if we want it, is Prometheus + Grafana in-cluster (already the plan) |

**A correction worth recording.** An earlier draft of this document said "ELB/ALB is not
emulated at all," and `infrastructure.md` said floci "emulates neither load balancer". Both
were wrong: the service list covers ELB v2 (ALB, NLB, target groups, listeners, routing
rules), CloudFront, WAF v2, ACM, AWS Backup and Route 53. The practical conclusion did not
change — Traefik still has to do the real ingress — but the *reason* did, and it matters for
the Terraform. These resources apply cleanly; they simply do nothing once applied. Only
Network Firewall is genuinely absent.

## The three tiers that actually matter

"Supported" is the wrong axis, because almost everything in the reference design is
supported. What varies is whether the emulated thing *does* anything:

| Tier | Resources | What `terraform apply` gives you |
| --- | --- | --- |
| **Does real work** | EKS (real k3s), RDS (real PostgreSQL), ElastiCache (real Redis), S3, ECR, SSM | A thing that functions — a Kubernetes API to `kubectl` into, a database to connect to |
| **Applies, but inert** | VPC, subnets, security groups, NAT and internet gateways, ALB, NLB, CloudFront, WAF, ACM, Route 53, AWS Backup | State you can create, describe and tag. Nothing routes, filters, caches or enforces |
| **Not there at all** | Network Firewall | An error that halts the apply |

The inert tier is the large one, and it is not a defect — it is what an emulator is. It is
still worth applying, because it makes the Terraform match the diagram and costs nothing;
it just has to be labelled so nobody reads a Web ACL in the state file as something that
filters traffic.

The third tier matters more than its size suggests: **one unsupported resource halts the
whole apply**, leaving everything created before it in state and everything after it
unrun. That, rather than tidiness, is the real argument for keeping unsupported resources
out of the applied path.

There is a fourth failure mode with no tier of its own — **a supported service with an
unsupported operation**. EKS is the example: cluster creation works, but add-ons, access
entries, identity provider configs and encryption config do not. So `aws_eks_cluster`
applies while `aws_eks_addon` fails.

## What can and can't be done — summary

**Can:** apply real Terraform (AWS provider, v1.10+) against it, covering essentially the
whole reference design; stand up an EKS cluster and get a live Kubernetes API you can
`kubectl` and Helm into; run a real PostgreSQL via the emulated RDS; store objects in
emulated S3; push and pull images through emulated ECR straight into the cluster; keep
secrets in SSM; create the whole VPC skeleton; snapshot and restore emulator state; run it
all in CI.

**Can't:** route a packet through a load balancer; enforce a security group; scale nodes
through EKS node-group APIs; fail over a Multi-AZ RDS; apply a Network Firewall; exercise
real IAM edge cases, quotas, or throttling; prove anything about actual AWS behaviour under
load or failure.

This is why [ADR 0001](adr/0001-terraform-verifies-runtime-deploys.md) splits the work:
floci verifies that the Terraform stands up, and a real local Kubernetes cluster runs the
app. Load and latency figures measured against the emulator would describe the emulator.

## To verify in I-1a — things the docs left unclear

Narrowed by ADR 0001. The items about running the app on emulated services are gone, since
the app no longer runs there; what remains is about the Terraform track. **Question 1 —
whether the community EKS module applies cleanly — is answered above**, and answered
without the emulator, because it turned out to be a question about the module rather than
about floci. Three remain, and all three need floci actually running:

1. Does an inert-tier resource — an `aws_lb`, a `aws_cloudfront_distribution`, a
   `aws_wafv2_web_acl` — actually apply, or does "supported" turn out shallower than the
   service list claims? Managed node groups belong here too: `aws_eks_node_group` alongside
   an `aws_launch_template` and an `aws_placement_group`.
2. What does floci return when an apply reaches an unimplemented operation: a clean error
   Terraform can report, or something that looks like success?
3. Does `FLOCI_SERVICES_EKS_MOCK=true` cover enough for the CI gate, so the Terraform job
   needs no Docker socket?

All three are settled by one apply, which is why the roadmap expects them to come from the
first CI run rather than from more reading. Question 2 is the one to be careful about: a
misconfiguration that reports success is the worst outcome available, and it is the only
one of the three that cannot be spotted by reading a plan.

Moot under ADR 0001, kept only as curiosities: whether Rails connects through the RDS auth
proxy, whether Active Storage works against floci's S3, and how permissive the emulated IAM
is. The app meets real PostgreSQL and real object storage on the other track.
