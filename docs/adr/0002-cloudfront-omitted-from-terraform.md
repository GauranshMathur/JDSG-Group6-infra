# ADR 0002 — CloudFront is omitted from the Terraform, and the omission is labelled

**Status:** Accepted
**Date:** 2026-08-13

## Context

`CLAUDE.md` says inert resources are applied and labelled: most of the reference design
creates cleanly against floci and then does nothing, so applying it anyway keeps the
Terraform matching the diagram, and labelling it stops anyone reading a Web ACL in the
state file as something that filters traffic. **CloudFront is named in that rule as an
example.**

It cannot be followed for CloudFront. Measured twice, in
[`floci.md`](../floci.md): floci *accepts* `CreateDistribution` — no error, no 404 — and
then returns an object incomplete enough that the AWS provider segfaults reading it back
(`nil pointer dereference` in `cloudfront.resourceDistributionFlatten`). The apply dies
with `Error: The terraform-provider-aws plugin crashed!`, taking the whole run with it.

Two things were checked before accepting this, and both closed off the obvious escapes:

- **Every provider version crashes.** A bisect applying one distribution against floci on
  `4.67.0`, `5.0.0`, `5.31.0`, `5.70.0`, `6.0.0` and `6.59.0` crashed on all six,
  identically — two major releases and roughly three years of provider history. This is
  not a regression waiting to be fixed upstream.
- **There is no way to skip one resource in an apply.** Terraform has no `-exclude` flag
  (checked on 1.13 and 1.15); only `-target`, and targeting everything-but-one is
  documented as exceptional recovery, not pipeline practice.

What is *not* broken is the rest of Terraform. The distribution plans fine — it appeared
in all thirteen resources of the spike's plan — so `fmt`, `validate` and `plan` all handle
it. Only `apply` dies.

## Decision

**CloudFront is not in the Terraform. The reference design keeps it, and every place it is
described says why the Terraform stops short.**

The edge chain in the Terraform therefore begins at the ALB. `docs/infrastructure.md`
continues to describe CloudFront as the front door, because it is the front door of the
design; it now carries the reason it is undeployable against the emulator, so the gap is
read as a recorded decision rather than an oversight.

## Cost

**The Terraform no longer matches the diagram, which is the property the "apply the inert
tier" rule exists to protect.** Someone comparing the two will find a service in one and
not the other, and the only thing preventing that from reading as a mistake is this record
and the notes pointing at it. That is a weaker guarantee than the rule gave, and it is the
real price here.

**The rule now has an exception, and exceptions spread.** "Inert resources are applied and
labelled" was absolute and therefore easy to apply. It is now "applied and labelled, except
where the emulator makes applying impossible", which requires judgement, and judgement
drifts. The mitigation is that the exception is named and evidenced rather than general:
CloudFront, for this measured reason.

**Nothing exercises the CloudFront configuration.** Under the rejected `count` option the
resource would at least be parsed, validated and planned, so a syntax error or a bad
attribute would surface. Omitted entirely, the configuration does not exist to be wrong —
which also means the day it is written for real AWS, it will be written from scratch and
unverified.

## Alternatives considered

**Keep it behind `count = var.emulated ? 0 : 1`.** The resource stays in the configuration,
reads as part of the design, is validated, and applies against real AWS. Rejected on
balance rather than on principle: it removes the resource from the *plan* as well when
emulated, so it buys presence-in-the-config at the cost of a variable whose only purpose is
to describe the emulator's shortcomings, and recovering the plan's completeness would mean
publishing a second plan that is never applied — which cuts against the
"apply the plan you published" rule in [`ci-cd.md`](../ci-cd.md) and is precisely the
confusion that rule exists to prevent. Omitting is more honest about what is happening than
a conditional that pretends the resource is merely switched off.

**Pin an older AWS provider.** Eliminated by measurement, above.

**Report it upstream and wait.** floci is MIT-licensed and its response is genuinely
incomplete; a provider that segfaults rather than erroring is arguably also a provider bug.
This is worth doing on its own merits — it is the only option that helps the next person —
but it fixes nothing on this milestone's timescale, so it is not a blocker for I-1b.

## Consequences to honour

- `docs/infrastructure.md` keeps CloudFront and says why the Terraform stops at the ALB.
- The architecture diagram still draws CloudFront. It should gain a marker distinguishing
  what is realized from what is reference-only; until it does, the diagram overstates what
  the Terraform builds.
- If the design is ever pointed at real AWS, CloudFront has to be written and tested from
  nothing — there is no configuration to reuse.
