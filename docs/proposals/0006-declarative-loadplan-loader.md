---
id: "0006"
title: "Declarative LoadPlan loader"
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

# Proposal 0006 — Declarative LoadPlan loader

> Format: mini (triage score 2/6 — new module, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose a `CordisLoader` module that applies a declarative list of plugin entries from decoded config, so that apps can be driven by YAML or JSON without code, as HANDOFF §10 anticipates. Unlike hard-coded `ctx.plugin` calls, the plan is validated before anything loads, at the cost of a string-keyed registry at the config boundary.

## Context and problem

All plugins are loaded by type in code. HANDOFF §10 defers a YAML/feature-flag loader. cordis-rs has an immutable validated `LoadPlan` whose structure fixes execution order only (never lifecycle ownership), with opaque `EntryId`s and a resolve key (`CONTEXT.md`, "LoadPlan").

## Goals and non-goals

**Goals**

- **G1** — Validate a plan before loading anything.
- **G2** — Report one outcome per entry.

**Non-goals**

- **NG1** — Hot reload of the plan file.
- **NG2** — Loader as a service.

## Proposal

```swift
let plan = try LoadPlan(entries: [
    .init(key: "sqlite", config: ["path": "main.db"]),
    .init(key: "users"),
])
let outcomes = await app.load(plan, resolver: registry)
```

Separate target `CordisLoader`. The only string key lives here, resolved to a typed plugin via a caller-supplied `PluginResolver`. Entries load in order; a failed entry is reported and loading continues, matching the kernel's local-failure rule. Entries get no parent relation beyond order.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | no new surface | manual wiring | Considered |
| Loader module | config-driven | string keys at boundary | Proposed |
| Macro-generated wiring | compile-time | macros out of scope | Rejected |

## Risks

Compatibility: new target, additive. Risk: stringly keys violate the typed-key rule inside the kernel; contained to this module. Rollback: remove the target.

## Open questions

1. Is config decoding (`Decodable`) owned by the plugin or by the resolver? (author)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | No | No, because decode ownership (type-erased config) and validation checks are unspecified; suggests a demo-local spike instead. Not fixed, escalated to decider. |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
