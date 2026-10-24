---
id: "0002"
title: "Scoped event routing"
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

**Accepted** on 2026-10-24 by Amine BENSALAH.

Accepted by the decider, overriding the reviewer's "No" (no concrete case beyond realms plus a tenant field). Conditions resolving the blocking items: the axis is named *zone* (not scope) to avoid the `Scope` collision; `ctx.zone(_ label: String)` returns a child context whose zone is a child of the current one (same label under the same parent is the same zone); a listener reaches an event when its zone is ancestor-or-self of the emit zone, and a listener with no zone is global and reaches every event; an emit with no zone reaches only global listeners; the default is no zone, so existing behaviour is unchanged; zones are inherited by derived contexts and are independent of `Scope`, realms and plugin lifetime; zones are not an authorization boundary. Open question 1 resolved accordingly.

## Amendments

<!-- Append-only after acceptance. -->
