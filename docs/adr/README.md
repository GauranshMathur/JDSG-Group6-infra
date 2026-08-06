# Architecture decision records

A record per decision that had a real alternative and a cost worth remembering. The point is
not to document everything — it is so that "why is it like this?" has an answer six months
later, including the answer "we knew, and here is what we accepted".

A decision with no genuine alternative does not need a record. It is a line in whichever
document it affects.

## Format

Context, then the decision, then the consequences — good *and* bad. An ADR that lists only
benefits is marketing, not a record. If a choice cost nothing, it probably was not a decision.

Records are immutable once accepted. When one is overturned, the new record supersedes it and
the old one stays, marked. The reasoning that turned out to be wrong is usually the most
useful part.

## Numbering

This series starts at 0001 and is this repository's own. ADR 0001 was numbered 0008 while the
application and infrastructure shared a repository; it was renumbered when they split, since
a series with a single record numbered 0008 tells the reader nothing except that something is
missing. Immutability applies to a record's *content* once accepted — not to which repository
it lives in.

The application's decision records, 0001 to 0007 in its own series, are in
[JDSG-Group6-app](https://github.com/GauranshMathur/JDSG-Group6-app/tree/main/docs/adr).

## Records

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-terraform-verifies-runtime-deploys.md) | Terraform is verified against the emulator; the app is deployed on a real local cluster | Accepted |
