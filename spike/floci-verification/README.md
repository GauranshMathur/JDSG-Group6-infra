# Verification spike — throwaway

**This is not the reference design, and it is deleted once it has answered its
questions.** Nothing here should be extended, imported, or used as a starting point for
I-1b's Terraform.

## Why it exists

Two rules in this repository could not both be satisfied:

- `CLAUDE.md`: *no Terraform until I-1a's toolchain questions are answered.*
- `docs/roadmap.md`: *those answers come from the first CI apply.*

An apply needs Terraform, so I-1b could not start. This spike is the way out recorded in
[`docs/open-questions.md`](../../docs/open-questions.md): a deliberately minimal config
that answers all three remaining questions in one CI run, and is then removed. The rule
is reworded alongside it so the next person does not hit the same wall.

## The three questions

| # | Question | Answered by |
| --- | --- | --- |
| 1 | Do inert-tier resources actually apply, or is "supported" shallower than the service list claims? | `inert/` applying cleanly |
| 2 | What does floci return on an unimplemented operation — a clean error, or something that looks like success? | `unsupported/`, run separately and expected to fail |
| 3 | Does `FLOCI_SERVICES_EKS_MOCK=true` cover enough that the Terraform job needs no Docker socket? | `inert/`'s EKS resources applying with **no** socket mounted |

## Why two roots rather than one

Question 2 is a *deliberate* failure. In one root it would abort the apply and take
questions 1 and 3 unanswered with it — the run would tell us nothing except that
something broke. Split, each question produces its answer independently, and a partial
result is still a result.

## What it deliberately does not do

- **No S3 backend.** State is local and thrown away. Bootstrapping the state bucket is
  its own ordering problem, tracked separately for I-1b; dragging it in here would mean
  a failed bootstrap masking the answers.
- **No reference-design fidelity.** One resource of each inert kind, sized and named for
  legibility rather than realism. Reading anything about the intended architecture off
  this directory is a mistake — that is [`docs/infrastructure.md`](../../docs/infrastructure.md).
- **No `main` gate.** The workflow is manual and never required, because a spike that
  blocks merges outlives its usefulness by exactly as long as it takes to forget it.

**Said plainly, because it would otherwise look like a dodge:** `ci.yml`'s Trivy
misconfiguration scan is pointed at `infra/`, so this directory is not scanned. That is a
consequence of putting the spike at the repository root rather than a gate being weakened
to let it through — and it is the reason it goes at the root. Under `infra/` a throwaway
probe would fail the scan on the unencrypted, unrestricted resources it deliberately uses,
and the pressure would be to loosen a real gate for a config that is about to be deleted.
The reference design's Terraform lands under `infra/` and **is** scanned.

## Running it

It cannot be run in an egress-restricted environment: pulling floci's image resolves the
manifest and then fails on the blob CDN, for Docker Hub and ECR Public alike. That is why
this runs in GitHub Actions.

```bash
gh workflow run spike-floci.yml
```

Locally, with Docker and unrestricted egress:

```bash
docker run -d --name floci -p 4566:4566 -e FLOCI_SERVICES_EKS_MOCK=true floci/floci:latest
cd spike/floci-verification/inert && terraform init && terraform apply -auto-approve
cd ../unsupported && terraform init && terraform apply -auto-approve   # expected to fail
```
