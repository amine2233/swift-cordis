---
id: "0004"
title: "Runtime snapshot and observation stream"
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

# Proposal 0004 — Runtime snapshot and observation stream

> Format: mini (triage score 2/6 — new public API, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose a read-only `ctx.snapshot()` and an `observations` async stream so that tools can show the live dependency graph, because HANDOFF §10 lists it as future work. Unlike reusing app events, observation carries no control power, at the cost of a stable record shape.

## Context and problem

State is visible only through `PluginStatusChanged`, `ServiceChanged` and `PluginFailed` events. There is no way to list plugins or visible slots. cordis-rs publishes five immutable record categories (residency, state, service visibility, listener registration, dispatch completion) plus a flat unordered snapshot; deleting every observer changes no outcome (`docs/v3-architecture.md`, "Events, update control, and observation"; ADR 0035).

## Goals and non-goals

**Goals**

- **G1** — List plugins with status and visible slots through a read-only `snapshot()`.

**Non-goals**

- **NG1** — An `observations()` stream: existing events already cover change notification. Add it only when a named consumer needs it.
- **NG2** — Persistent journal or replay.
- **NG3** — Exposing Registry internals.

## Proposal

```swift
let snap = app.snapshot()          // plugins: [PluginInfo], slots: [SlotInfo]
```

`snapshot()` is synchronous on `@CordisActor`, built from `Registry.forks` and `slots`, returning value types with opaque `PluginID`s. Record shapes are marked provisional.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | free | no tooling | Rejected |
| Reuse existing events | already there | no list, no snapshot | Partial |
| Snapshot only | tooling, no control | new shapes (provisional) | Proposed |
| Snapshot + `observations()` stream | live view | continuation ownership, backpressure | Deferred |

## Risks

Compatibility: additive. Risk: record shape becomes public contract; mark provisional. Security: snapshot may expose service names, N/A for values.

## Open questions

1. Which consumer (CLI graph view, SwiftUI inspector) justifies adding a stream later? (decider)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | Yes, if… (blocking fixed: stream cut to deferred, snapshot only) |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
