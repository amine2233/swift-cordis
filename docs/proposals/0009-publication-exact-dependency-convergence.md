---
id: "0009"
title: "Publication-exact dependency convergence"
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

# Proposal 0009 — Publication-exact dependency convergence

> Format: mini (triage score 3/6 — touches reactivity core, hard to reverse, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose restarting dependents only when the visible provider occurrence changes, not on every provide, so that republishing or mutating a service payload does not cascade. Unlike the global generation counter, an occurrence identity makes drift mean what it says, at the cost of reworking `resolve()` and `Entry`.

## Context and problem

Every `provide` bumps a global generation, and a fork restarts when the stored generation of any injected slot differs (`Plugin.swift:87-103`, `docs/ARCHITECTURE.md`, Reactivity 1-3). A provider that restarts because of its own config republishes, and all dependents restart even if the new value is equivalent. cordis-rs tracks the exact publication occurrence: payload mutation of the same occurrence changes no target, while removing or providing a new occurrence does; visibility, not declared metadata, drives drift (`docs/v3-architecture.md`, "Services and dependency convergence", ADR 0031).

## Goals and non-goals

**Goals**

- **G1** — Mutating a service in place does not restart dependents.
- **G2** — Dependents restart exactly when a different provider becomes visible or the slot becomes missing.

**Non-goals**

- **NG1** — Cross-process identity.
- **NG2** — Changing the public `ServiceKey` API.

## Proposal

```swift
try await ctx.provide(CacheKey.self, cache)        // new occurrence: dependents restart
try await ctx.update(CacheKey.self) { $0.limit = 10 }   // same occurrence: no restart
```

`Entry` gets an `occurrence: OccurrenceID` (opaque, allocated per successful `provide`); `Fork.resolve()` snapshots occurrences instead of generations. A new `ctx.update(Key, mutate)` mutates the value of the occurrence this context published. The fork-recheck path in `Registry.changed` is unchanged. The global generation counter stays for logging only.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | works today | over-restarts on republish | Considered |
| Equality check on values | no new id | needs Equatable on every service | Rejected |
| Occurrence identity | exact, no Equatable | touches core and tests | Proposed |

## Risks

Compatibility: observable restart behaviour changes for republished equal values; every existing lifecycle test must still pass. Rollback is costly after release (reactivity semantics), so prototype behind the existing tests first. Security: N/A.

## Open questions

1. Is in-place `ctx.update(Key, mutate)` worth adding, or only the occurrence identity? (decider)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | No, because the stated cascade is already caused by withdraw, and ctx.update is a separate feature; not fixed, escalated to decider | none |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
