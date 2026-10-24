---
id: "0005"
title: "Generation-owned timer effects"
type: mini
status: in-review
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

# Proposal 0005 — Generation-owned timer effects

> Format: mini (triage score 1/6 — additive helper, ≥2 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose `ctx.after` and `ctx.every` that cancel automatically when the registering scope is disposed, so that plugins stop leaking timers. Unlike a hand-written `Task.sleep`, cancellation is tied to the existing `Scope`, at the cost of a clock dependency.

## Context and problem

Plugins that need timers must hand-roll `Task` plus `ctx.onDispose` cancellation, and the kernel forbids fire-and-forget `Task {}` (`AGENT.md`). cordis-rs ships `cordis-timer` as an optional leaf crate over narrow core seams; timer operations are a generation-owned resource whose cleanup commits to the registering generation (`ROADMAP.md`, `docs/v3-architecture.md`).

## Goals and non-goals

**Goals**

- **G1** — Timers cancel on dispose, restart and update.
- **G2** — Time source is injectable: tests use a small in-repo manual `Clock` (no third-party dependency).

**Non-goals**

- **NG1** — Throttle or debounce.
- **NG2** — Calendar scheduling.

## Proposal

```swift
try await ctx.every(.seconds(30)) { await refreshToken() }
```

Lives in `Cordis` (not `CordisKernel`), built on `ctx.effect` and `ContinuousClock` behind a `Clock`-generic initializer. The tick runs on `@CordisActor`. Teardown cancels the task first, then awaits it, so a tick awaiting a graph mutation cannot stall disposal. The task is owned by the effect, so no orphan work survives.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | no code | leaks | Rejected |
| Helper in Cordis | zero kernel change | one more API | Proposed |
| Separate package | isolation | overhead for 30 lines | Considered |

## Risks

Compatibility: additive. Risk: a long non-cancellable tick body delays teardown; mitigated by cancel-then-await. Rollback: delete the file.

## Open questions

1. Should a tick body that throws stop the timer or just report? (author, proposed: report via 0001 if accepted, otherwise ignore the error; this proposal does not depend on 0001)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | Yes, if… (blocking fixed: in-repo test clock; cancel-then-await) |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
