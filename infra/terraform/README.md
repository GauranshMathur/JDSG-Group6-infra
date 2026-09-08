# The reference design, as Terraform

Every directory here matching `NN-name` is **its own Terraform root**, with its own
workspace and its own state. They are applied in directory order — `00` before `10` before
`20` — by the `Terraform` workflow, which is the only thing that ever applies them.

Terraform does not read subdirectories, so this is not cosmetic: each layer is a separate
`terraform init` and `terraform apply`, and each shows up as its own run in HCP Terraform
with its own plan.

**They all run in one CI job, because they must share one emulator.** floci is created and
destroyed with the job; a second job would get a second, empty emulator, and a layer would
be building on subnets that exist only in another layer's state.

## Layers

**The workspace is `twitter-clone-NN`, where NN is the directory's prefix** — `10-network`
writes its state to `twitter-clone-10`.

Foundation holds keys and nothing else. Anything the application stores lives with the data
layer, so the media bucket sits beside the database rather than under a name that only ever
meant "built first".

| Layer | Workspace | Holds | Status |
| --- | --- | --- | --- |
| `00-foundation` | `twitter-clone-00` | KMS keys — and nothing else | applied |
| `10-network` | `twitter-clone-10` | VPCs, subnets, gateways, routing, NACLs, security groups, transit gateway | scaffolded, empty |
| `20-edge` | `twitter-clone-20` | ACM, NLB, ALB, WAF, Route 53 | not started |
| `30-platform` | `twitter-clone-30` | ECR, IAM, SSM | not started |
| `40-data` | `twitter-clone-40` | Media bucket, and RDS when it lands | applied |
| `50-cluster` | `twitter-clone-50` | EKS, node groups | not started |
| `60-reliability` | `twitter-clone-60` | Backup, S3 replication, failover | not started |

> **A typo here does not fail — it creates.** If `cloud.tf` names a workspace that does not
> exist, `terraform init` creates it, and a workspace created that way defaults to **Remote**
> execution. The run then executes on HashiCorp's workers, which have no floci on their
> loopback, and the apply dies with `connection refused` after nine retries. Three runs were
> lost to exactly this. Check the name, and check the execution mode of anything new.

Layers below `60` are planned, not promised — see [decisions.md](../../docs/decisions.md).

## Inside a layer

```
10-network/
  versions.tf           terraform and provider pins
  cloud.tf              the workspace this root writes state to
  providers.tf          the AWS provider, and its endpoint inventory
  variables.tf          inputs
  locals.tf             names, CIDRs, availability zones, shared tags
  vpc.tf                one file per group of resources — keep them short
  subnets.tf
  ...
  outputs.tf            what the layers above are allowed to depend on
```

One file per resource group, not one file per layer. A file long enough to need scrolling
twice is a file that wants splitting.

## Conventions

**The endpoints block is an inventory.** `providers.tf` lists an endpoint per AWS service
the root touches. Add a service, add its endpoint — otherwise the provider aims at real AWS
and fails on the fake credentials.

**Inert resources carry a tag.** Most of this design applies against floci and then does
nothing: the emulator routes no packet and enforces no rule. Those resources carry
`local.inert` (`Emulation = "inert"`), so a security group in state is never mistaken for
one that filters traffic. It is a tag rather than a comment deliberately — it survives into
state and shows up in every plan.

**No modules.** There is one of everything, so a module would add indirection without reuse,
and it would hide the cross-references that the file split exists to make findable.

**Cross-layer references go through outputs.** A layer declares in `outputs.tf` what it
exposes; the layer above reads it with `terraform_remote_state`. The producing workspace
must have remote state sharing enabled in HCP Terraform, or the read is denied.

## Adding a layer

1. Create the workspace in HCP Terraform, CLI-driven, named `twitter-clone-NN` for the
   directory's prefix. Create it **before** the first init — see the warning above.
2. Set **Execution mode: Agent** against the `jdsg` pool, and **Terraform version 1.13.1**.
3. Enable **remote state sharing** if a layer above will read its outputs.
4. Create the directory with the scaffolding files above; copy `.terraform.lock.hcl` from a
   neighbour, since the provider and its constraint are the same.

The workflow picks it up automatically — it globs `[0-9][0-9]-*/`, so nothing lists the
layers by hand.

## Deliberately absent

**CloudFront** — floci accepts `CreateDistribution` and returns an object that segfaults the
AWS provider on read-back, on every version from 4.67 to 6.59. The diagram keeps it; the
Terraform starts at the NLB.

**Global Accelerator** — not in floci's service registry at all.

Both are recorded in [decisions.md](../../docs/decisions.md) and [floci.md](../../docs/floci.md).
