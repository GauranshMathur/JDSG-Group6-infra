# floci — the local AWS emulator

[floci](https://floci.io/floci/) is a free, MIT-licensed local AWS emulator: 69 services on
one endpoint (`localhost:4566`), LocalStack-compatible, works with Terraform by pointing
the provider at that endpoint. Run it with
`docker compose -f infra/docker/floci-compose.yml up -d`.

## How deep the emulation goes

"Supported" is the wrong axis — almost everything in the reference design is supported.
What varies is whether the emulated thing *does* anything:

| Tier | Resources | What `terraform apply` gives you |
| --- | --- | --- |
| Does real work | EKS (real k3s in Docker), RDS (real PostgreSQL), ElastiCache (real Redis), S3, ECR, SSM | A thing that functions |
| Applies, but inert | VPC, subnets, security groups, NAT/IGW, transit gateway, ALB, NLB, WAF, ACM, Route 53, AWS Backup | State entries. Nothing routes, filters or enforces |
| Not there at all | Network Firewall, Global Accelerator, EC2 placement groups | A clean error that halts the apply |
| Breaks the provider | CloudFront | Create accepted, read-back segfaults the AWS provider |

The real-Docker tier needs the Docker socket mounted. No region isolation, no quotas, no
throttling, no packet filtering — the emulator proves *wiring*, never AWS behaviour.

## Measured facts

From two throwaway spikes, since deleted (Actions runs 31680455895 and 31684334790):

- **CloudFront cannot be applied.** floci accepts `CreateDistribution`; the AWS provider
  segfaults reading the response back — identically on 4.67, 5.0, 5.31, 5.70, 6.0 and
  6.59. Not a regression; no pin escapes it. `plan` handles it fine; only `apply` dies.
- **Placement groups are refused** (`UnsupportedOperation`, HTTP 400) — an enabled service
  is not a complete service. Nothing in the design needs one.
- **Unimplemented operations fail loudly** — 404 for an absent service, 400 for a missing
  operation. No silent success was observed, which is what makes an apply worth gating on.
- **EKS mock mode (`FLOCI_SERVICES_EKS_MOCK=true`) needs no Docker socket** — cluster and
  node group apply in under a second as metadata. This is what CI uses.
- **An ALB takes ~60 seconds to create** — the provider waits out a state transition the
  emulator never makes. Budget CI time accordingly once the load balancers land.
- **The community EKS module is two variables from applying**: at defaults, only
  `encryption_config` (defaults to `{}`, not `null`) and IRSA's real outbound TLS
  handshake fail against floci. Whether to use it anyway is in
  [decisions.md](decisions.md) under Undecided.
