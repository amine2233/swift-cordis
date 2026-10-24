---
id: "0010"
title: "Performance benchmark baseline"
type: mini
status: accepted
authors: ["Amine BENSALAH <amine.bensalah@intech-consulting.fr>"]
reviewers: []
decider: "Amine BENSALAH"
created: 2026-10-24
review-deadline: 2026-10-29
discussion: ""
supersedes: ""
amends: ""
amended-by: ""
superseded-by: ""
---

# Proposal 0010 — Performance benchmark baseline

> Format: mini (triage score 1/6 — additive tooling, ≥2 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose a small benchmark target with a recorded baseline so that regressions in the graph are noticed, because the serialised single actor is our main scaling limit. Unlike a performance target, it is only regression evidence, at the cost of a maintained target.

## Context and problem

There are no measurements of reconcile cost. The design serialises every mutation on `@CordisActor` and cascades restarts through `Fork.refresh`. cordis-rs records a baseline for spawn plus settle, event emit with 0/1/N listeners, service publication affecting 0/1/N dependents, restart and update, and uses a 15% same-machine review trigger that prompts human review rather than failing CI (`ROADMAP.md`, "Performance regression evidence").

## Goals and non-goals

**Goals**

- **G1** — Measure a fixed set of graph operations.
- **G2** — A threshold crossing triggers review, not a CI failure: `scripts/bench-compare.sh` diffs against `docs/performance.md` and prints a warning above 15%.

**Non-goals**

- **NG1** — A headline throughput claim.
- **NG2** — Cross-machine comparisons.

## Proposal

```text
swift run -c release cordis-bench      # prints ns/op per scenario
scenarios (start with 3): load N plugins, provide affecting N dependents, update
```

New executable target `CordisBench` using `ContinuousClock` only, no third-party package. Results and machine info go in `docs/performance.md`. The target uses only the public `Context` API. Run manually or by `mise` task, never in shared CI (noisy).

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | free | blind to regressions | Considered |
| In-repo executable | no dependency, simple | hand-rolled timing | Proposed |
| package-benchmark | richer | third-party dependency, needs approval | Rejected |

## Risks

Compatibility: additive target. Risk: noisy numbers; mitigated by 'review, not fail'. Rollback: delete the target.

## Open questions

1. None blocking (manual runs only).

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | scenarios cut to 3; compare script wires G2; public API only |

## Decision

**Accepted** on 2026-10-24 by Amine BENSALAH.

Conditions: start with three scenarios (load N plugins, provide affecting N dependents, update); executable target `CordisBench` using only the public `Context` API and `ContinuousClock`; `scripts/bench-compare.sh` diffs against `docs/performance.md` and prints a warning above 15%; a `mise` task `bench`; manual runs only, never in CI.

## Amendments

<!-- Append-only after acceptance. -->
