---
id: "0001"
title: "Attempt-all teardown with failure reporting"
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

# Proposal 0001 — Attempt-all teardown with failure reporting

> Format: mini (triage score 2/6 — public teardown semantics, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose letting teardown closures throw, running every closure regardless, and reporting failures as a `TeardownFailed` event, so that one bad cleanup cannot leave resources behind or hide an error. Unlike today's non-throwing `Disposer`, failures become visible, at the cost of a source-compatible but wider `Disposer` type.

## Context and problem

`Disposer` is `@CordisActor () async -> Void` (`Sources/CordisKernel/Scope.swift:9`). `Scope.dispose()` runs handles in reverse order. A teardown cannot report failure, so authors swallow errors with `try?`. cordis-rs drains cleanups LIFO, attempt-all, and reports a failing or panicking item as a secondary diagnostic without stopping the drain (`docs/v3-architecture.md`, "Resources and cleanup").

## Goals and non-goals

**Goals**

- **G1** — Every teardown keeps running when one throws (`Scope.dispose()` already runs every handle; this stays true once closures can throw).
- **G2** — A thrown teardown error is observable.

**Non-goals**

- **NG1** — Retrying failed teardowns.

## Proposal

```swift
try await ctx.effect {
    let socket = try await open()
    return { try await socket.close() }   // may throw
}
app.on(TeardownFailed.self) { log($0.plugin, $0.error) }
```

Only the `Disposer` input type widens to `@CordisActor () async throws -> Void`. `Disposable.callAsFunction()` stays non-throwing: it catches the error and passes it to a `failureHandler` closure that `Scope` receives at init. `Context.root()` wires that handler to `registry.emit(TeardownFailed(plugin:error:))`, with `error: any Error` like `PluginFailed`. Non-throwing closures still compile; callers of `Disposable()` are unchanged.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | no change | errors silently lost | Rejected |
| Keep non-throwing, document `try?` | zero cost | hides failures | Rejected |
| Throwing + event | visible, attempt-all | wider type | Proposed |

## Risks

Compatibility: source-compatible for closure authors and for `Disposable` callers (it stays non-throwing); `Scope.init` gains an internal parameter. Rollback: revert the typealias. Security/migration: N/A.

## Open questions

1. None blocking.

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | Yes, if… (2 blocking fixed: emitter wiring, Disposable stays non-throwing) |

## Decision

**Accepted** on 2026-10-24 by Amine BENSALAH.

Conditions: `Disposable` stays non-throwing; only the `Disposer` input type widens. `Scope` receives an internal failure handler wired by `Context.root()` to `registry.emit(TeardownFailed(plugin:error:))`; `plugin` is the owning context name (`root` when none). Open question 1 resolved: `error` is `any Error`, as in `PluginFailed`.

## Amendments

<!-- Append-only after acceptance. -->
