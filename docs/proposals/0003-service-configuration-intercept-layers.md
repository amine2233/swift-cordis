---
id: "0003"
title: "Service configuration intercept layers"
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

# Proposal 0003 — Service configuration intercept layers

> Format: mini (triage score 1/6 — additive, ≥2 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose ordered, context-attached configuration layers for a service key so that wrappers such as logging or caching compose without editing the provider. Unlike per-plugin config, layers apply by service and compose outer-to-inner, at the cost of an extra context axis.

## Context and problem

Services are raw values keyed by `ServiceKey`. Cross-cutting wrappers need either a decorator plugin that re-provides the key (conflict error today, `CordisError.serviceConflict`) or edits to the provider. cordis-rs has an `intercept` axis: matching layers compose outer-to-inner under the Service contract; it is not event middleware or routing (`CONTEXT.md`, "intercept").

## Goals and non-goals

**Goals**

- **G1** — A layer wraps a service value at provide time.
- **G2** — Layer order is deterministic.

**Non-goals**

- **NG1** — Per-call interception (middleware).
- **NG2** — Authorization.

## Proposal

```swift
let traced = app.intercept(DatabaseKey.self) { db in TracingDatabase(db) }
await traced.plugin(UserRepositoryPlugin.self)   // sees the wrapped database
```

`ServiceKey` gains an optional `static func compose(layer:over:)`. A `Context` stores layers per `ServiceID`; `provide` applies them outer-to-inner before storing the entry. The stored value is the composed one; the generation counter is bumped once.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | nothing to build | boilerplate decorators | Considered |
| Decorator plugin | no kernel change | needs second key and name clash | Considered |
| Intercept layers | composable | axis + ordering rules | Proposed |

## Risks

Compatibility: additive. Risk: a layer that throws leaves the provider failed (rollback by existing fork failure path). Migration: N/A.

## Open questions

1. Do layers apply to values already provided when the layer is added? (author, proposed: no)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | No | No, because `compose` hook unexplained, inheritance unspecified, late layers never re-apply. Not fixed, escalated to decider. |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
