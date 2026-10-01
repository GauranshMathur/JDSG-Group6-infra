# Decisions

One entry per decision, dated, newest last. An entry says what was decided, why, and what
it cost when the cost is real. When a decision is reversed, edit the entry and say so —
the old text stays in git history. The full ADRs this file replaced are in git history
too, deleted 2026-08-18 on the drawing-board reset.

## 2026-08-05 — Never a real AWS account

The enterprise AWS architecture is the *reference design*: drawn and documented as a real
account would be, realized entirely locally. Terraform is written against the AWS provider
so that pointing at real AWS would be an endpoint change, not a rewrite — that is the whole
of the relationship with AWS. **No real cloud resources, ever.** Cost: AWS behaviour —
quotas, IAM edge cases, managed-service failure modes — stays unproven, permanently.

## 2026-08-05 — One root, no modules; Terraform stops at AWS

There is one of everything, so modules would add indirection without reuse. Files split by
concern (`s3.tf`, `eks.tf`, …). Kubernetes objects are manifests, never `kubernetes`
provider resources — the provider cannot plan against a cluster that does not exist yet.
**The single root was reversed on 2026-09-27** — see the entry below. No modules still holds.

## 2026-08-05 — Images come from GHCR

The app already publishes `ghcr.io/gauranshmathur/twitter-clone-web` on every release. The
reference design says ECR; the running cluster pulls from GHCR. Cost: gives up floci's
automatic ECR-to-k3s wiring, so the cluster needs egress and possibly a pull secret.

## 2026-08-13 — CloudFront is omitted from the Terraform

Measured, twice: floci accepts `CreateDistribution` and returns an object that segfaults
the AWS provider on read-back — on every provider version from 4.67 to 6.59, so no pin
escapes it, and Terraform has no way to skip one resource in an apply. The diagram keeps
CloudFront as the front door; the Terraform's edge chain starts at the NLB. Cost: the
Terraform doesn't match the diagram at the edge, and if this ever points at real AWS the
CloudFront config gets written from scratch.

## 2026-08-18 — One system, one companion artifact

Previously "two tracks" (ADR 0001 in history). The reframe: **the system** is the app
running on a local k3d cluster — real PostgreSQL, real object storage, Traefik ingress —
and that is where anything runtime-shaped (load, resiliency, failover) happens. **The
Terraform** is a companion artifact that expresses the reference design and is verified in
CI against floci. The insight that forced the split still holds: floci routes no packets
and enforces nothing, so nothing runtime-shaped may ever depend on it. Cost: two
descriptions of the cluster that can drift; the manifests stay cluster-agnostic to limit it.

## 2026-08-18 — Local Terraform state; CI applies on the PR run

Previously: state in the emulator's own S3 with a CLI bootstrap step, plan published as a
PR comment and artifact, apply on merge (ADRs 0003/0004 in history). All of it existed to
mimic production patterns against a backend that died with the emulator's container and
durably stored nothing. Now: local state (gitignored), and the `Terraform` check runs
`fmt → init → validate → plan → apply` against a fresh floci on the pull request itself —
with a throwaway emulator, an apply is free and side-effect-free, and a green check means
"this configuration stands up from nothing". Cost: none of the production state/backend
patterns are demonstrated here; if that lesson is ever wanted, it is a decision away.
**Reversed on 2026-09-08** — the lesson was wanted; see the entry below.

## 2026-08-18 — The NLB fronts the ALB

Ingress runs internet gateway → NLB → ALB, not straight to the ALB as the diagram
previously showed. The NLB is the perimeter's L4 entry point — one fixed-address front
door that hands connections on without inspecting them — and the ALB behind it does host
and path routing, TLS and the OIDC sign-in hop. Cost: an extra hop and a second load
balancer on the applied path, which against floci is roughly another minute of apply time.

## 2026-08-18 — Trivy is the one security gate

`ci.yml` scans the whole tree (secrets, vulnerable dependencies, misconfiguration) and
fails on any fixable HIGH or CRITICAL. Do not weaken it to make a build pass; if a finding
is genuinely not actionable, say so in the PR.

## 2026-09-08 — State and runs move to HCP Terraform, on a self-hosted agent

The reversal the 2026-08-18 entry left open. State, locking and run history live in HCP
Terraform, in one workspace, `twitter-clone`. Terraform is never run by hand — the
`Terraform` workflow is the only thing that applies this configuration, which is why one
workspace is enough and why there is no local path to keep in step with it.

Runs execute on a **self-hosted agent** rather than HashiCorp's own workers, because a
worker in HashiCorp's cloud has no route to the floci the job starts on the runner, and
putting a fake AWS on the public internet to give it one is not on the table. The workflow
starts the agent beside the emulator and stops it at the end of the job, so the single
agent the free tier allows is only ever in use while a run is.

This does not touch "never a real AWS account" — HCP Terraform is not AWS, and nothing here
bills or provisions. It does make HCP Terraform the first external service the project
depends on besides GitHub and GHCR.

Cost. The check now needs two repository secrets, so a pull request from a fork cannot run
it. The job grows an agent container and a registration wait on top of the emulator it
already had. And there is no way to apply this configuration except through the pipeline —
which is the intent, but it does mean a broken workflow is a broken apply, with no manual
fallback.

Not a cost, and written down so nobody later mistakes it for one: the workspace's state
outlives the emulator it describes, so every plan reads as a first-time create. Nothing
here needs a resource to survive a run. The pipeline is the artifact, and "stands up from
nothing" is the whole of what the check claims.

## 2026-09-27 — Layered roots, applied in directory order

One root becomes one per layer. Every directory under `infra/terraform/` matching `NN-name`
is its own Terraform root with its own workspace and state, applied in directory order by
the workflow, which globs `[0-9][0-9]-*/` rather than listing them. Each writes to
`twitter-clone-NN` for its directory prefix. **Modules are still refused** — the reversal is
about roots, not about indirection.

The reason is readability. A single root grows to roughly 125 resources across the full
design, and a `network.tf` holding thirty of them is not reviewable. Separate roots also
give a plan and an apply per layer in HCP Terraform, and force each layer to declare in
`outputs.tf` what the layers above may depend on, rather than reaching into anything.

**All layers apply in one CI job**, because they must share one emulator: floci is created
and destroyed with the job, so a second job would get an empty one and a layer would build
on subnets that exist only in another layer's state. Ordering is the directory prefix;
destroy runs the same list backwards.

Cost, and it is not small. Seven workspaces to create and configure by hand as the layers
land, each needing Agent execution — and a workspace whose name does not exist yet is
created by `terraform init` with **Remote** execution, which cannot reach the emulator, so a
typo silently produces a run that dies on `connection refused`. `versions.tf`, `cloud.tf`
and `providers.tf` duplicate into every layer — around twenty near-identical short files,
because Terraform has no include. Each root is a separate HCP run, so the pipeline pays
upload, queue and plan overhead per layer: roughly five extra minutes once all seven exist,
against a thirty-minute job timeout. And a layer can only read another layer through
`terraform_remote_state`, a coupling a single root did not have.

This lands one layer at a time. `00-foundation` is the move itself and nothing else: the
same six resources, the same workspace, a new path and a workflow that iterates.

## 2026-09-30 — Layers find each other by name where they can

`40-data` needs `00-foundation`'s KMS key. It resolves it with a `data "aws_kms_alias"`
lookup against the emulator, not with `terraform_remote_state`. The lookup needs nothing
configured in HCP Terraform — remote state sharing is a per-workspace setting that has to be
switched on by hand and cannot be checked from here — and it works because the workflow
applies `00` before `40` in the same job, so the alias already exists when the data layer
plans. `terraform_remote_state` stays the answer where there is no stable name to look up.

Cost: a weaker contract. An output is declared and reviewed; a lookup depends on a string.
Rename the alias in foundation and the data layer breaks at plan time, not at review. And a
lookup reads the live emulator, so it only works inside the one job that applies both
layers — which is the only way anything here is ever applied.

## 2026-10-01 — A layer's branch is named for its workspace

A change to a layer comes from a branch named exactly for that layer's workspace —
`twitter-clone-10` for `10-network` — one layer per branch. Branches are no longer named for
the feature. Because a branch name exists only once, a workspace has at most one change in
flight, which is the point: no two pull requests take turns writing different configurations
into the same workspace. The `Terraform policy` job holds it on every pull request, and applies
come only from those branches, a push to `main`, or a run by hand from either. Everything else
— CI, docs — keeps `type/<short-description>` and gets no apply on its pull request. Applies
run one at a time across the repository, locked on the apply job rather than the workflow.

Cost. A workflow change can no longer be proven by an apply before it merges: its pull request
runs the policy and nothing else, and the first apply under the new workflow is the push to
`main`. Local checks against stubs have to carry that weight. Two changes to the same layer
cannot be prepared side by side; the second waits for the first to merge. And the lock is a
check, not a wall, until `protect-main` requires it — the ruleset requires no status checks yet.

## 2026-10-01 — Security groups in the network layer; open rules designed out first

Every security group in the design — load balancers, cluster nodes, the database — is defined
in `10-network`, and the layers that create those things attach them. One file holds every
rule, so what may talk to what is reviewed in one place. Cost: network defines groups before
anything uses them, every rule change is a `twitter-clone-10` change, and an upper layer finds
its group by lookup.

Trivy refuses any rule open to `0.0.0.0/0`, and the gate stays as it is. Open rules are
designed out where the design allows: the NLB takes HTTPS only from CloudFront's origin-facing
managed prefix list, which is what "nothing behind the perimeter sees the internet directly"
means. floci has no AWS-managed lists and refuses the reserved name for any other, so the
lookup's name is a variable defaulting to AWS's own; the workflow seeds a stand-in with a
documentation range as its one entry and points the layer at it through a generated
`emulator.auto.tfvars`. Network ACLs stay at the VPC default rather than declaring a public ACL that must
admit return traffic from anywhere. What can't be designed out gets an inline exception naming
one check on one resource, with the reason above it. There is one: nodes out to the internet on
443, for image pulls from GHCR (no stable range to narrow to) and for AWS APIs through NAT.
Cost: every exception is a rule the scanner no longer reads, so each one has to be argued in
review instead.

## 2026-10-01 — Terraform owns the ALB; the cluster only binds pods to it

The design had the AWS Load Balancer Controller create the ALB from a Kubernetes `Ingress`.
Instead `20-edge` defines the NLB, the ALB, the ALB's HTTPS listener and the pods' target group,
and the controller's part shrinks to a `TargetGroupBinding` that registers pod addresses into
that target group. The NLB targets the ALB, which a controller-made ALB would make awkward: its
ARN would exist only after the cluster did. And with the ALB in the perimeter VPC and the pods in
the application VPC, the targets are addresses across the transit gateway, registered with
availability zone `all`. That is supported, and simpler to see when the target group sits in
Terraform beside the rest of the edge.

Cost. Routing rules no longer come from the `Ingress`, so a new host or path is a Terraform change
rather than a manifest change. The `TargetGroupBinding` is AWS-only, so it belongs with the
reference design's EKS configuration and never in the cluster-agnostic manifests the local
cluster runs, where Traefik does the ingress.

---

## Undecided

Each is argued in the issue named beside it and, once settled, becomes a dated paragraph
above. The issue is where the arguing happens; this file is where the answer lives.

- **EKS: community module or hand-rolled?** The module applies against floci with exactly
  two overrides (`encryption_config = null`, `enable_irsa = false`) but that cluster no
  longer matches the reference design, and the module drags in a nested KMS module.
  Decide before `eks.tf` is written — [#18](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/18).
- **k3d, kind or minikube** for the local cluster. k3d is the likely answer (k3s in
  Docker, ships Traefik and ServiceLB). Decide when the cluster work starts —
  [#23](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/23).
- **MinIO or floci's S3** as the object storage the running app uses. Decide when media
  storage is wired up — [#23](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/23).
- **Solid Cache or Redis** for the shared cache — an app-repo change, forced the moment
  there are two replicas — [#24](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/24).
- **Load-test tooling** — k6 and Toxiproxy are the candidates, and the app repository
  already has a k6 suite worth reusing. Decide when load testing starts —
  [#25](https://github.com/GauranshMathur/JDSG-Group6-infra/issues/25).
- **Should a pull request apply into the shared workspace at all?** Narrowed on 2026-10-01:
  only a branch named for a workspace applies, and only one per workspace at a time. Still
  open: such a branch closed rather than merged leaves its state ahead of `main`, as #35 did
  in 2026-09. Plan-only on pull requests, with apply on `main`, would close it.
