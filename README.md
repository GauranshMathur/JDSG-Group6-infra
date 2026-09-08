# JDSG-Group6 — Infrastructure

The infrastructure for the [JDSG-Group6 Twitter clone](https://github.com/GauranshMathur/JDSG-Group6-app):
an enterprise AWS architecture as the *reference design*, realized entirely locally.

**This is a proof of concept, and there will never be a real AWS account.** Nothing bills,
nothing deploys to a cloud. The AWS design is drawn as a real account would be, then stood
up against a local emulator ([floci](docs/floci.md)) and a local Kubernetes cluster.

![AWS reference architecture](docs/diagrams/aws-reference-architecture.svg)

The app repository publishes a container image to GHCR
(`ghcr.io/gauranshmathur/twitter-clone-web`); everything about where that image runs lives
here. That image is the whole interface between the two repositories.

## Documentation

| Document | What is in it |
| --- | --- |
| [Architecture](docs/architecture.md) | The reference design, layer by layer, and how each piece is realized locally |
| [Decisions](docs/decisions.md) | Every decision taken, dated, with what it cost — and the short list still undecided |
| [floci](docs/floci.md) | The emulator: how deep each service goes, and the measured facts |

## Repository layout

```
infra/
├── terraform/        # The reference design as Terraform — one root per layer, applied
│                     # in directory order; see infra/terraform/README.md
├── kubernetes/       # Manifests, cluster-agnostic (not started yet)
└── docker/           # Compose files: the emulator, and PostgreSQL for local dev
.github/workflows/    # CI (lint + security scan), Terraform (HCP Terraform run against floci), diagram render
docs/                 # The three documents above, plus the diagram source
```

## Running things

**Terraform is never run by hand.** State, locking and run history live in
[HCP Terraform](docs/decisions.md), and the `Terraform` workflow is the only thing that
applies this configuration: it starts a throwaway floci on the runner, starts an agent
beside it, and dispatches the run. To see a plan and an apply, push a change under
any layer under `infra/terraform/`, or run the workflow by hand from the **Actions** tab — which also
takes a `destroy` option that tears the resources down again in the same job, so the
workspace goes 6 resources to 0 and back.

Do not queue a run from the HCP Terraform UI. It will wait forever: the workspace executes
on an agent, and the only agent that ever exists is the one the job starts and stops around
the run.

One-time setup, in the HCP Terraform organization named in each layer's `cloud.tf` (or set
`TF_CLOUD_ORGANIZATION`):

1. Create an agent pool and an agent token.
2. Create a workspace per layer — `twitter-clone-00`, `twitter-clone-10`, … — each
   **Execution mode: Agent** against that pool, *before* the first init. See
   [`infra/terraform/README.md`](infra/terraform/README.md).
3. Add two repository secrets — `TF_API_TOKEN` (a user or team token, for the CLI) and
   `TFC_AGENT_TOKEN` (the agent token). A pull request from a fork gets neither, so the
   Terraform check cannot run on one.

Locally there is only the runtime, never Terraform:

```bash
# PostgreSQL, for when the app moves off SQLite
docker compose -f infra/docker/app-compose.yml up -d

# The AWS emulator, if you want one to poke at by hand
docker compose -f infra/docker/floci-compose.yml up -d
```

## What's next

Each of these is a [tracked issue](https://github.com/GauranshMathur/JDSG-Group6-infra/issues) —
the issues are the queue, this list and `docs/` remain the record.

**Track A, the Terraform.** S3 and KMS are applied; the rest goes in slices:

- [#19](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/19) network — VPC, subnets, security groups, IGW, NAT, transit gateway
- [#20](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/20) edge — NLB in front of ALB, WAF, ACM, Route 53
- [#21](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/21) data and platform — RDS, ECR, IAM, SSM
- [#22](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/22) the cluster itself, blocked on [#18](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/18) — community EKS module or hand-rolled

**Track B, the runtime.** Independent of Track A and of the emulator:

- [#23](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/23) the local cluster — k3d, Traefik, real PostgreSQL, object storage
- [#24](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/24) the app served on it, and the three changes it forces in the app repository
- [#25](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/25) resiliency demos and load testing — rolling deploys under load, node loss, zone loss, HPA
