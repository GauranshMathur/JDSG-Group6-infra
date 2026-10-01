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
will write its state to `twitter-clone-10`.

| Layer | Workspace | Holds | Status |
| --- | --- | --- | --- |
| `00-foundation` | `twitter-clone-00` | KMS keys — and nothing else | applied |
| `10-network` | `twitter-clone-10` | VPCs, subnets, gateways, routing, transit gateway, and every layer's security groups | applied |
| `20-edge` | `twitter-clone-20` | ACM, NLB, ALB, WAF, Route 53 | not started |
| `30-platform` | `twitter-clone-30` | ECR, IAM, SSM | not started |
| `40-data` | `twitter-clone-40` | Media bucket, and RDS when it lands | media bucket applied |
| `50-cluster` | `twitter-clone-50` | EKS, node groups | not started |
| `60-reliability` | `twitter-clone-60` | Backup, S3 replication, failover | not started |

`00-foundation`, `10-network` and `40-data` exist. Foundation holds keys and nothing else;
anything the application stores lives with the data layer, beside where the database will,
rather than under a name that only ever meant "built first". `10-network` holds the three VPCs,
two public subnets in the perimeter routed out through its internet gateway with a NAT
gateway in each, two private ones in the application VPC, and a transit gateway joining the
two. The application VPC's only way out runs through it: transit gateway, the perimeter's NAT
in the same zone, then the internet gateway. It also holds the security groups for the load
balancers, nodes and database, which the layers creating those attach. Network ACLs are left
at the VPC default on purpose — see the conventions below. The other rows are the intended order, not a promise — see
[decisions.md](../../docs/decisions.md).

> **A typo here does not fail — it creates.** If `cloud.tf` names a workspace that does not
> exist, `terraform init` creates it, and a workspace created that way defaults to **Remote**
> execution. The run then executes on HashiCorp's workers, which have no floci on their
> loopback, and the apply dies with `connection refused` after nine retries. Three runs were
> lost to exactly this. Check the name, and check the execution mode of anything new.
>
> The workflow now checks both before any `init`: each layer's workspace must match its
> directory prefix, exist, and be on Agent execution. The prefix check also catches the quieter
> mistake — a layer copied from a neighbour that still names the neighbour's workspace, which
> fails nothing and writes its state over the other layer's.

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
`local.inert` (`Emulation = "inert"`), so a security group in state is never mistaken for one
that filters traffic. A tag rather than a comment deliberately — it survives into state and
shows up wherever the resource is read.

**Security groups live in `10-network`, open to `0.0.0.0/0` only where they must be.** Every
rule is reviewable in one file, and other layers attach groups rather than defining them. The
NLB admits only CloudFront's origin-facing prefix list. The one rule open to the internet,
nodes out on 443, carries a `#trivy:ignore` naming that single check, with the reason above
it. Any new exception gets the same treatment: one check, one resource, the reason in the
code. Network ACLs stay at the VPC default, since a declared public ACL would have to admit
return traffic from anywhere.

**No modules.** There is one of everything, so a module would add indirection without reuse,
and it would hide the cross-references that the file split exists to make findable.

**Cross-layer references, two ways.** A layer declares in `outputs.tf` what it exposes.
Where the thing has a stable public name — a KMS alias, a VPC tag — prefer a **data source
lookup** against the emulator: it needs nothing configured in HCP Terraform, and it works
because layers apply in order in one job, so the lower layer's resource already exists.
`40-data` finds its key this way, by `alias/twitter-clone-s3`. Where there is no such name,
read the output with `terraform_remote_state`, and enable remote state sharing on the
producing workspace or the read is denied. The lookup's cost is a weaker contract — it
depends on a string, so renaming it below breaks the layer above at plan time, not review.

## Adding a layer

**One layer, one pull request, from a branch named for its workspace.** A change to
`10-network` is made on a branch called exactly `twitter-clone-10`. A layer is built,
reviewed and merged before the next one starts — the numbering is the dependency order, and
a branch that fills two of them is reviewing neither. Because a branch name can exist only
once, each workspace has at most one change in flight, and the name frees when the branch is
deleted on merge.

The `Terraform policy` check holds this on every pull request:

| Branch | Layers it changes | Result |
| --- | --- | --- |
| `twitter-clone-NN` | exactly `NN-*` | applies |
| `twitter-clone-NN` | none, another, or more than one | refused |
| anything else (`ci/…`, `docs/…`) | none | passes, no apply |
| anything else, `feat/…` included | any | refused |

A push to `main` applies, and so does a run by hand from `main` or a `twitter-clone-NN`
branch — from nowhere else. Applies run one at a time across the repository, since every run
applies every layer into its shared workspace. Shared files — the workflow, this README — go
on a `ci/` or `docs/` branch, and their first apply is the push to `main` after merge.

0. Branch from `main` as `twitter-clone-NN`, for the new layer's prefix.
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
