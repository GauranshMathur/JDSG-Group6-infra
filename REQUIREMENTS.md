# Requirements

Numbered and testable, so that "is it done?" has an answer other than an opinion. Status is
updated when a requirement's state actually changes, not when work on it starts.

**A note on numbering.** These start fresh at `I-x` rather than continuing the app
repository's `N-x` series. The two repositories release independently, and a requirement
whose ID only makes sense by reference to another repository is worse than a renumbered one.
Where a requirement here depends on the app, it says so and links.

---

## 1. Design

| ID | Requirement | Status |
| --- | --- | --- |
| I-1.1 | The reference design is documented layer by layer — edge, ingress, cluster, data, recovery | Met — [`docs/infrastructure.md`](docs/infrastructure.md) |
| I-1.2 | The design is drawn, using the official AWS icon set, and the drawing is the source of truth rather than a screenshot | Met — [`docs/diagrams/`](docs/diagrams/), draw.io XML rendered to SVG by CI |
| I-1.3 | Every piece of the design says how it is realized locally, including the pieces that cannot be | Met — the tables in `infrastructure.md` and `floci.md` |
| I-1.4 | The emulator's depth is recorded honestly: what does real work, what applies but is inert, what is absent | Met — the three tiers in [`docs/floci.md`](docs/floci.md) |
| I-1.5 | The remaining toolchain questions are answered before Terraform is written | **Met** — all four answered and recorded in [`docs/floci.md`](docs/floci.md). The EKS module question was answered by reading the module; the other three by a throwaway spike applying Terraform against floci in CI ([run 31680455895](https://github.com/GauranshMathur/JDSG-Group6-infra/actions/runs/31680455895)), since deleted. The inert tier applies, unimplemented operations fail loudly, and EKS mock mode needs no Docker socket — with two exceptions the run found: placement groups are refused, and CloudFront crashes the AWS provider. I-2.x is no longer gated on this |

## 2. Terraform — the design, verified

Track A of [ADR 0001](docs/adr/0001-terraform-verifies-runtime-deploys.md). Proves the
configuration stands up; never runs the app.

| ID | Requirement | Status |
| --- | --- | --- |
| I-2.1 | The reference design exists as Terraform — VPC, EKS, RDS, S3, ECR, IAM, SSM and the edge chain | Planned — I-1b. **CloudFront is excluded by [ADR 0002](docs/adr/0002-cloudfront-omitted-from-terraform.md)**: it cannot be applied against the emulator on any provider version, so the Terraform's edge chain starts at the ALB. WAF, ACM and Route 53 are unaffected |
| I-2.2 | One root, no modules, files split by concern | Planned |
| I-2.3 | `terraform fmt -check` passes, and CI fails on any drift | Planned |
| I-2.4 | `terraform validate` passes | Planned |
| I-2.5 | `terraform plan` is saved and published as a build artifact, and the apply applies *that* plan | Planned |
| I-2.6 | `terraform apply` against a clean emulator succeeds, and is a CI gate | Planned |
| I-2.7 | State lives in S3 with locking, never on disk and never committed | Planned — S3 backend on the emulator; Terraform 1.10+ gives S3-native locking via `use_lockfile`, so no DynamoDB table |
| I-2.8 | Resources that apply but do nothing are labelled as such, so nobody reads them as functional | Planned. The converse now needs labelling too: CloudFront is in the design and *not* in the Terraform ([ADR 0002](docs/adr/0002-cloudfront-omitted-from-terraform.md)), so the gap reads as a decision rather than an omission |
| I-2.9 | Terraform describes AWS only; Kubernetes objects are manifests | Planned — ADR 0001 |
| I-2.10 | No real cloud resource is ever created | **Met, and permanent.** The provider points at the emulator; there is no AWS account |

## 3. Runtime — the app, actually running

Track B. Independent of track A and of the emulator.

| ID | Requirement | Status |
| --- | --- | --- |
| I-3.1 | A local Kubernetes cluster runs, with ingress | Planned — I-1d |
| I-3.2 | The app serves on it: image pulled from GHCR, migrations run, `/up` green behind ingress | Planned — I-1e |
| I-3.3 | The app runs against real PostgreSQL, not SQLite | Planned — needs [an app change](https://github.com/GauranshMathur/JDSG-Group6-app) |
| I-3.4 | Media is stored in S3-compatible object storage, so a redeploy does not delete every avatar | Planned — needs an app change |
| I-3.5 | The cache and rate limiter are shared, not per-process, so two replicas agree | Planned — needs an app change |
| I-3.6 | Manifests are cluster-agnostic — no EKS-only storage classes, no ALB ingress annotations | Planned. This is what keeps the two cluster descriptions from drifting |
| I-3.7 | Rolling deploys happen without downtime, under load | Planned — I-1f |
| I-3.8 | Losing a node reschedules its pods; losing a zone reschedules the zone | Planned — I-1f |
| I-3.9 | The HPA scales replicas under load, and node count follows | Planned — I-1f |
| I-3.10 | Behaviour under load and injected latency is measured and written down | Planned — I-1g |

## 4. Delivery

| ID | Requirement | Status |
| --- | --- | --- |
| I-4.1 | All work reaches `main` through a pull request | Met |
| I-4.2 | A pull request merges only once every required check has passed | Not met — `main` has no required status checks yet |
| I-4.3 | Commits follow Conventional Commits | Met |
| I-4.4 | The rendered architecture diagram cannot drift from its source | Met — a workflow re-renders the SVG on every push that changes the `.drawio` |
| I-4.5 | The pipeline runs the same commands a person would run locally | Planned — lands with the Terraform in I-1b |

## 5. Security

| ID | Requirement | Status |
| --- | --- | --- |
| I-5.1 | Committed secrets are scanned for on every pull request | Met — Trivy secret scanning |
| I-5.2 | Terraform and Kubernetes manifests are scanned for misconfiguration; any fixable HIGH or CRITICAL fails the build | Met — Trivy config scan, already running against `infra/` |
| I-5.3 | No credential, key or endpoint for a real cloud account exists in this repository | **Met, and permanent** |
| I-5.4 | Terraform state is never committed | Planned — enforced by `.gitignore` and the S3 backend |

---

## 6. Deferred by proof-of-concept scope

Not open questions so much as known gaps, recorded so they are known rather than forgotten.

| ID | Requirement | Status |
| --- | --- | --- |
| I-6.1 | The design is proven against real AWS | **Never.** There is no account, by design. The emulator proves wiring; AWS behaviour — quotas, IAM edge cases, managed-service failure modes — stays unproven |
| I-6.2 | Load and latency figures describe production capacity | Deferred — figures measured locally describe the app on local hardware. Valid for finding N+1s and scaling cliffs, not for capacity planning |
| I-6.3 | The DR region is exercised | Deferred — reference-only. floci has no region isolation, so cross-region replication and failover stay on paper |
| I-6.4 | Backups are taken and restores are tested | Deferred — a PostgreSQL dump/restore against the local database is the most that is planned |
| I-6.5 | Secrets are managed by something other than the emulator's SSM | Deferred — nothing here holds a real secret |

---

## 7. Out of scope

- Any real cloud resource, in any provider, ever.
- Application code. It lives in [JDSG-Group6-app](https://github.com/GauranshMathur/JDSG-Group6-app).
- Multi-environment promotion — staging and production. There is one local environment.
- GitOps reconciliation with Flux. Agreed as a direction, explicitly not on the critical path.
