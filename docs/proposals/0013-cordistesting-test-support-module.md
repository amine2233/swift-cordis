---
id: "0013"
title: "CordisTesting test-support module"
type: mini
status: accepted            # draft | in-review | accepted | rejected | implemented | superseded | abandoned
authors: ["Amine BENSALAH <amine.bensalah@intech-consulting.fr>"]
reviewers: []
decider: "Amine BENSALAH"
created: 2026-10-24
review-deadline: 2026-10-29
discussion: ""           # PR link
supersedes: ""           # "<id> §x.y" when replacing (part of) another proposal
amends: ""               # proposal this one extends without contradicting
amended-by: ""
superseded-by: ""
---

# Proposal 0013 — CordisTesting test-support module

> Format: mini (triage score 2/6 — new public product, two credible options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose a `CordisTesting` library product, depending on `CordisKernel` only, that gives plugin and module authors the test pieces that cannot be reused today: a public deterministic `ManualClock`, a bounded `settle(until:)`, and a scoped `withTestApp` that always disposes the graph and records lifecycle and failure events. Unlike copying these into every test target, authors state only what they check, at the cost of a small public API that must stay stable.

## Context and problem

`ManualClock` (`Tests/CordisTests/ManualClock.swift`) and `settle(until:)` (`Tests/CordisTests/TimerTests.swift:19`) live in one test target, so no other target or downstream package can use them. Teardown is easy to forget: `defer` cannot `await`, so a test that throws before `await app.dispose()` leaks the graph. Failures such as `PluginFailed` or `TeardownFailed` are only observable by registering listeners by hand in each test. `Context.root()` itself is a one-liner (67 occurrences across 12 test files) and is not the problem. `Probe` (`Tests/CordisKernelTests/GraphTests.swift:5`) is a plugin-config string log used in 8 kernel test files and is out of scope. Proposal 0011 expects third-party module authors, who would have to rebuild all of this.

## Goals and non-goals

**Goals**

- **G1** — `withTestApp { ctx, events in … }` runs a body against a fresh root context and always disposes it, including when the body throws.
- **G2** — `events` records `PluginFailed`, `PluginStatusChanged`, `ServiceChanged` and `TeardownFailed` in emission order, including those emitted while the graph is disposed, and `withTestApp` returns the final `RecordedEvents` so a test can assert on teardown failures after the body ends.
- **G3** — `ManualClock` and `settle(until:)` are public in `CordisTesting`, and `CordisTests` uses them (the copies in the test target are deleted).
- **G4** — `CordisTesting` does not link the `Testing` framework, so it works from Swift Testing and XCTest.

**Non-goals**

- **NG1** — Replacing `Probe` or any plugin-config log; kernel tests keep their own helpers.
- **NG2** — Assertion macros, a Swift Testing trait, or generated mock plugins (plugins stay static types; fakes are small `Plugin` enums or `ctx.provide` on the root).
- **NG3** — Test support for external module processes (0011), added when that exists.
- **NG4** — Re-exporting `Cordis` with `@_exported import` (would add its own source-compatibility promise); deferred.

## Proposal

```swift
import CordisTesting

@Test func consumerStartsWhenDatabaseAppears() async throws {
    let events = try await withTestApp { app, _ in
        let consumer = await app.plugin(UserRepositoryPlugin.self)
        #expect(consumer.status == .pending)

        try await app.provide(DatabaseKey.self, FakeDatabase())
        #expect(consumer.status == .active)
    }
    #expect(events.failures.isEmpty)   // includes anything thrown during dispose
}
```

New target `CordisTesting` with `dependencies: ["CordisKernel"]` (no sugar layer, so kernel tests may use it too) and a matching library product. Public surface, all `@CordisActor`:

- `withTestApp(_ body: (Context, RecordedEvents) async throws -> Void) async rethrows -> RecordedEvents` (`@discardableResult`): creates `Context.root()`, registers the recorder first, runs `body`, then `await ctx.dispose()` in every case. Listeners are torn down in reverse registration order, so the recorder is removed last and still sees failures emitted by other teardowns; a test pins this.
- `RecordedEvents`: `all: [any Event]`, `ofType(_:) -> [E]`, and `failures: [any Event]` (the `PluginFailed` and `TeardownFailed` entries, whose `error` is `any Error` and not `Equatable`, so tests inspect it with `as?`).
- `ManualClock` (`advance(by:)`, `sleeperCount`), moved from `CordisTests` unchanged in behaviour.
- `@discardableResult settle(until:) -> Bool`: yields at most 10 000 times and returns whether the condition held; existing call sites compile unchanged and may add an `#expect`.

Staging: step 1 moves `ManualClock` and `settle` (about 80 lines already written); step 2 adds `withTestApp` and `RecordedEvents`.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Do nothing | no new API | helpers stay unusable downstream, easy to leak a graph | Rejected |
| Only move `ManualClock` and `settle` | smallest change, no new design | does not fix dispose or event recording | Step 1 of the proposal |
| Internal shared test-support target | no public API | not usable by downstream packages or modules (0011) | Rejected |
| `TestApp` wrapper forwarding `Context` methods | one object | duplicates the `Context` API; every new method needs a forward | Rejected |
| Custom Swift Testing trait (`@Test(.cordisApp)`) | least code per test | depends on `Testing`, couples the product to one framework | Deferred |
| `CordisTesting` product, closure-scoped | reusable, framework-neutral | small public surface to keep stable | Proposed |

## Risks

Compatibility: new product only, nothing existing changes. "Experimental" means a 0.x note in the README; SwiftPM cannot enforce it. `ManualClock` is `@unchecked Sendable` with a lock (as today); making it public makes its thread-safety a contract, so keep the implementation and add a concurrent-advance test. Production code MUST NOT depend on `CordisTesting`; the README says to add it to test targets only. The `PluginStatusChanged` order for a plugin that goes pending, loading, active was not traced for this document (to verify in the tests). Rollback: delete the product and restore the two helpers in `CordisTests`.

## Open questions

1. Does the recorder see `TeardownFailed` raised by teardown closures registered by the body? (author, to verify with a test before step 2)
2. Should `settle` later take a timeout `Duration` instead of an iteration count? (author, proposed: keep the count, it is deterministic)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |
| 2026-10-24 | design-proposal-reviewer | Yes, if… | 3 blocking fixed: evidence corrected (67 occurrences, not the real problem; justified by ManualClock, settle, missing dispose), Probe replacement dropped, dependency changed to CordisKernel only. Also: TestApp wrapper dropped for `(Context, RecordedEvents)`, events after dispose returned from `withTestApp`, `settle` returns a discardable Bool, `@_exported` deferred, staging added |

## Decision

**Accepted** on 2026-10-24 by Amine BENSALAH.

Conditions: implement step 1 (move `ManualClock` and `settle`) and step 2 (`withTestApp`, `RecordedEvents`) in one change; open question 1 is answered by a test before `withTestApp` is relied on; `CordisTesting` depends on `CordisKernel` only and does not link `Testing`; no `@_exported import`.

## Amendments

<!-- Append-only after acceptance. -->
