---
id: "0008"
title: "Update and replace semantics"
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

# Proposal 0008 — Update and replace semantics

> Format: mini (triage score 1/6 — small API clarification, ≥2 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose skipping no-op updates and documenting why we do not add a separate `replace`, so that equal configs stop restarting a plugin and its dependents. Unlike cordis-rs, which keeps `update` and `era_swap` as two operations, we keep one because our dependency edges are re-resolved on every reconcile.

## Context and problem

`update` always stops and restarts, even for an equal config (`Plugin.swift:195`). cordis-rs distinguishes same-Fiber `update` (same identity, new generation) from `era_swap` (old Fiber ends, fresh identity, fresh dependency edges); edges are fixed for an era (`docs/v3-public-interface.md`, "PreparedChange"). Our `resolve()` re-reads edges on each reconcile (`Plugin.swift:89`), so the reason for `era_swap` (retargeting) does not exist here.

## Goals and non-goals

**Goals**

- **G1** — `update` with an equal config does nothing.
- **G2** — The decision not to add `replace` is written down.

**Non-goals**

- **NG1** — Adding an `era_swap` equivalent.
- **NG2** — Diffing configs field by field.

## Proposal

```swift
public func update(_ config: P.Config) async   // no-op when status == .active and config == last applied
```

`Fork` (not the `PluginHandle` struct) stores the last successfully applied config as `Any?`. The single `update` skips only when the fork is `.active` and `config as? any Equatable` equals it, so there is no second overload. After a failed apply nothing is recorded, so retrying the same config re-runs `apply`. Disposing and loading the plugin again remains the way to get a fresh identity.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | nothing to build | needless restarts and cascades | Considered |
| Equatable short-circuit | tiny, safe | only for Equatable configs | Proposed |
| Add `replace` | parity with cordis-rs | no use case; edges already re-resolve | Rejected |

## Risks

Compatibility: observable change only for equal configs (fewer restarts); a caller relying on `update` with an equal value as a forced restart would stop restarting; no such caller exists in tests or the demo (checked), and no `restart()` API exists today, so add one only if a use case appears. Rollback: delete the overload.

## Open questions

1. None blocking.

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | blocking fixed: single update with runtime Equatable check; state on Fork; recorded only on success; question closed |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
