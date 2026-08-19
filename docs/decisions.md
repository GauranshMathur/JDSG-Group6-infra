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
