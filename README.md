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
├── terraform/        # The reference design as Terraform, verified in CI against floci
├── kubernetes/       # Manifests, cluster-agnostic (not started yet)
└── docker/           # Compose files: the emulator, and PostgreSQL for local dev
.github/workflows/    # CI (lint + security scan), Terraform (HCP Terraform run against floci), diagram render
docs/                 # The three documents above, plus the diagram source
```

## Running things

Terraform state and run history live in [HCP Terraform](docs/decisions.md), and the runs
execute on a self-hosted agent standing next to the emulator — HashiCorp's workers cannot
reach a floci on localhost. So there is a one-time setup before the first apply.

**One-time, in HCP Terraform.** In the organization named in `infra/terraform/cloud.tf`
(or set `TF_CLOUD_ORGANIZATION`):

1. Create an agent pool and an agent token.
2. Create two workspaces, both tagged `twitter-clone`, both **Execution mode: Agent**
   against that pool — `twitter-clone-local` and `twitter-clone-ci`.
3. `terraform login`, or export `TF_TOKEN_app_terraform_io`.
4. For CI, add two repository secrets: `TF_API_TOKEN` (a user or team token) and
   `TFC_AGENT_TOKEN` (the agent token). Without them the Terraform check cannot run,
   which is also why it cannot run on a pull request from a fork.

**Then, to apply locally:**

```bash
# The local AWS emulator
docker compose -f infra/docker/floci-compose.yml up -d

# The agent that runs Terraform against it. Host networking, so it reaches
# the same localhost:4566 the provider defaults to.
docker run -d --name tfc-agent --network host \
  -e TFC_AGENT_TOKEN -e TFC_AGENT_NAME=local hashicorp/tfc-agent:latest

# Apply. TF_WORKSPACE picks the workspace; the run happens on the agent.
cd infra/terraform && TF_WORKSPACE=twitter-clone-local terraform init && terraform apply

# Stop the agent when you are done — the free tier allows one at a time, and
# leaving this one up will starve a CI run.
docker stop tfc-agent && docker rm tfc-agent

# PostgreSQL, for when the app moves off SQLite
docker compose -f infra/docker/app-compose.yml up -d
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
