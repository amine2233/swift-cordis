---
id: "0002"
title: "Scoped event routing"
type: mini
status: draft
authors: ["Amine BENSALAH <amine.bensalah@intech-consulting.fr>"]
reviewers: []
decider: ""
created: 2026-10-24
review-deadline: 2026-10-29
discussion: ""
supersedes: ""
amends: ""
amended-by: ""
superseded-by: ""
---

# Proposal 0002 — Scoped event routing

> Format: mini (triage score 2/6 — new public axis, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose an optional event-scope axis on `Context` so that a listener only receives events dispatched from the same scope or a descendant, because today every listener is global. Unlike the time `Scope`, this is an independent routing relation, at the cost of one more `Context` axis.

## Context and problem

`Registry.emit` delivers to every listener of the event type (`Sources/CordisKernel/Registry.swift:93`). In a multi-tenant graph a tenant plugin sees other tenants' events. cordis-rs routes by a rooted Scope relation: a listener is reached when its registration scope is ancestor-or-self of the dispatch scope, unless explicitly global; Scope implies no lifecycle or service relation (`CONTEXT.md`, "Scope").

## Goals and non-goals

**Goals**

- **G1** — Listeners can be restricted to a scope subtree.
- **G2** — Default behaviour stays global, so nothing existing changes.

**Non-goals**

- **NG1** — Using event scope for authorization.
- **NG2** — Tying event scope to plugin lifetime.

## Proposal

```swift
let tenantA = app.eventScope("a")
tenantA.on(OrderPlaced.self) { ... }       // sees only a and descendants
await tenantA.emit(OrderPlaced())          // reaches a-listeners + global ones
await app.emit(OrderPlaced())              // reaches only global listeners
```

`Context` gains an `eventScope: EventScopeID?` (nil = global). `on` records it; `emit` delivers to a listener when its scope is nil or an ancestor-or-self of the emitter's scope. The `Registry` keeps the scope parent map. Scope never affects `Scope` disposal.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | simple | cross-tenant leakage | Rejected |
| Filter inside handlers | no kernel change | every handler repeats it | Rejected |
| Scope axis | matches cordis-rs | extra axis | Proposed |

## Risks

Compatibility: additive, nil default. Rollback: remove the axis. Security: not an authorization boundary and must be documented as such.

## Open questions

1. Should a global emit reach scoped listeners, as the ancestor rule in cordis-rs implies for global listeners only? (decider)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | No | No, because no concrete case beyond realms + a tenant field in the event; semantics inconsistent (global emit vs Q1); name collides with Scope. Not fixed, escalated to decider. |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
