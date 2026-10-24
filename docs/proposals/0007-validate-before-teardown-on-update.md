---
id: "0007"
title: "Validate before teardown on update"
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

# Proposal 0007 — Validate before teardown on update

> Format: mini (triage score 2/6 — changes failure behaviour, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose an optional `Plugin.validate(config:)` that runs before `update` tears anything down, so that a config that is malformed in shape leaves the running plugin untouched. Errors that only appear in `apply` (a bad DSN, say) still cascade. Unlike today, where a failing `apply` already destroyed the old instance, this keeps the service alive, at the cost of one optional static requirement.

## Context and problem

`PluginHandle.update` calls `fork.reconfigure`, which stops the plugin and re-applies it (`Sources/CordisKernel/Plugin.swift:195`). If the new `apply` throws, the fork is `.failed`, its services are withdrawn, and every dependent drops to pending. One typo in a config takes down the plugin and its whole subtree. cordis-rs runs update through a pre-commit policy pipeline; a veto or pre-commit failure leaves the old configuration and generation intact (`docs/v3-architecture.md`, "Events, update control, and observation", ADR 0034).

## Goals and non-goals

**Goals**

- **G1** — A rejected config changes nothing: same instance, same status, no cascade.
- **G2** — `update` reports whether it was applied.

**Non-goals**

- **NG1** — A general middleware pipeline of listeners.
- **NG2** — Validating the first `apply` (initial config errors already fail locally).

## Proposal

```swift
enum SQLitePlugin: Plugin {
    static func validate(config: String) throws {          // new, optional, default no-op
        guard !config.isEmpty else { throw ConfigError.empty }
    }
}
let outcome = await db.update("")      // .rejected(error); old DB keeps running
```

`validate` is a pure, synchronous `static` requirement with a default empty implementation. `validate` takes no `Context`, so it checks config shape only. `update` returns `UpdateOutcome { applied, rejected(any Error) }` (`@discardableResult`); callers read `handle.status` for an `apply` failure after validation, which still follows the existing rollback path (`.failed`, `PluginFailed`).

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | no change | bad config cascades | Rejected |
| Try new apply first, then swap | catches apply errors too | needs two live instances, breaks single-provider slot | Rejected |
| Static `validate` | cheap, no cascade on common errors | does not catch runtime apply errors | Proposed |

## Risks

Compatibility: additive with a default. `update` gains a discardable return value. Rollback: remove the requirement. Security: N/A.

## Open questions

1. Should `update` simply `throw` on validation error instead of returning an outcome enum? (author, proposed: enum, so callers do not need `try`)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | blocking fixed: dropped failedAfterApply; validate scope stated; summary no longer oversells |

## Decision

**Accepted** on 2026-10-24 by Amine BENSALAH.

Conditions: `failedAfterApply` is dropped; `update` returns `UpdateOutcome { applied, rejected(any Error) }` (`@discardableResult`); callers read `handle.status` for an `apply` failure after validation. `validate(config:)` is a static, synchronous, `Context`-free requirement with a default no-op, so it checks config shape only. Open question 1 resolved: an outcome enum, not `throws`.

## Amendments

<!-- Append-only after acceptance. -->
