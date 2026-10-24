# Architecture

## One actor

`@CordisActor` is a single global actor. Every graph mutation (provide, withdraw, start, stop) runs on it,
so reactive restarts are deterministic. Heavy work belongs inside the services, not the kernel.

## Building blocks (Sources/CordisKernel)

| File | Type | Role |
|---|---|---|
| Scope.swift | `Scope`, `Disposable` | LIFO, idempotent teardown. Time axis. |
| Service.swift | `ServiceKey`, `Slot`, `Inject`, events, `CordisError` | Typed service identity and plugin dependencies. |
| Registry.swift | `Registry` | Per-graph state: slots (with a generation counter), live forks, listeners. |
| Plugin.swift | `Plugin`, `Fork`, `PluginHandle` | A plugin application and its pending/loading/active/failed/disposed lifecycle. |
| Context.swift | `Context` | The only API a plugin sees: services, composition, effects, events, isolation. |

## Reactivity

1. `ctx.provide` bumps a global generation and stores an `Entry` in the slot.
2. `Registry.changed` emits `ServiceChanged` and calls `Fork.refresh()` on every fork that injects the slot.
3. `Fork.reconcile` compares the generations it started with against the current ones:
   missing required service → stop + pending; changed generation → stop + start; otherwise nothing.
4. `refresh` is re-entrancy safe: a change arriving mid-reconcile sets `needsReconcile` and is handled by the same loop.
   Slots the fork provides itself are ignored for its own dependencies.
5. `Context.provide` registers a withdraw in the plugin's scope, so stopping the plugin withdraws the service,
   which cascades to its dependents.

## Convergence

Each successful `provide` allocates an opaque `Entry.occurrence`; `Fork.resolve` snapshots occurrences, so a fork restarts
exactly when the provider occurrence it depends on is replaced or disappears. The global generation is kept: the snapshot
exposes it and it orders slots.

Honest note: this does not change which restarts happen today. Every `provide` bumps the generation and allocates an
occurrence together, so the two comparisons are equivalent, and no scenario was found where a dependent restarts although
the occurrence it depends on is unchanged (republishing is by definition a new occurrence). The behavioural gain is
`ctx.update(Key.self) { (value: inout K.Value) in … }`, which mutates the value this context published without changing
occurrence or generation: dependents are not restarted and no `ServiceChanged` is emitted. It throws
`CordisError.notPublished` if this context did not publish the slot. Dependents holding the old value only see the change
if the value is a reference type or they re-read the slot.

## Space

A `Slot` is `(service, realm)`. `ctx.isolate(Key.self, label:)` returns a child context resolving that key in another realm.
Same label = shared realm, no label = private anonymous realm.

## Zones

An optional event-routing axis, independent of `Scope`, realms and plugin lifetime. `ctx.zone("a")` returns a child context
whose zone is a child of the current one (same label under the same parent = same zone); derived contexts
(`isolate`, `zone`, plugins) inherit it. A listener is reached when it has no zone (global) or its zone is
ancestor-or-self of the emit zone; an emit from no zone reaches only global listeners. The default is no zone.

Zones are a routing convenience, **not an authorization boundary**: any code holding a context can create or emit into any zone.

## Intercept

`ctx.intercept(Key.self) { value in ... }` returns a child context holding an ordered list of layers for that service.
Layers are inherited by `isolate` and by plugins loaded through the context. `provide` applies them at provide time,
last-registered first, so the first-registered layer is the outermost wrapper; the registry stores the wrapped value
with a single generation bump. Layers are never retroactive: values already provided are untouched, and adding a layer
restarts nothing. The closure is non-throwing; conflict behaviour is unchanged.

Alternative with no kernel support: a decorator plugin that injects the base service under one key and provides the
wrapped value under a second key.

## Failure model

`apply` throwing rolls back the fork's scope, sets `.failed`, and emits `PluginFailed`. The rest of the graph keeps running.
`PluginHandle.update` first runs the static, `Context`-free `Plugin.validate(config:)`; a throw returns `.rejected(error)` and leaves the running instance, its status, services and dependents untouched. Only errors thrown later by `apply` follow the rollback path above.
Two different contexts providing the same slot raise `CordisError.serviceConflict`; the second plugin fails.

Teardowns (`Disposer`) may throw. `Scope.dispose()` still runs every teardown in reverse order, and each thrown error is
emitted once as `TeardownFailed(plugin:error:)` (`plugin` is the owning context name, `root` for the graph root).
`Disposable()` itself never throws.

## Snapshot

`ctx.snapshot()` (synchronous, on `@CordisActor`) returns an immutable `RuntimeSnapshot` copy of the graph:
`plugins: [PluginInfo]` (opaque `PluginID`, name, status, parent) and `slots: [SlotInfo]` (service, realm, providing `PluginID?`, generation).
Plugins are listed in registration order, slots in provision order. Disposed plugins are unregistered, so they are not listed.
It carries no control capability and no observation stream (deferred, Proposal 0004). The record shapes are provisional.

## Known limitation

`Scope.collect` on an already-disposed scope runs the teardown in a `Task` (the signature is synchronous),
so that one path is not ordered with respect to other events.

## Timers

`Cordis` (not the kernel) adds `ctx.after(_:clock:_:)` and `ctx.every(_:clock:_:)`, built on `ctx.effect`.
Each call owns one `Task` running on `@CordisActor`; its teardown cancels the task, then awaits it, so a tick
that is mid-mutation cannot stall disposal. Timers are therefore cancelled on scope dispose, plugin dispose,
restart and update. The clock is injectable (`some Clock<Duration>`, default `ContinuousClock`); tests use a manual clock.
Tick bodies are non-throwing in this version.

## Update semantics

`PluginHandle.update` is a no-op when the fork is `.active` and the new config equals the last successfully applied one
(runtime `Equatable` check; non-`Equatable` configs always restart). The applied config is recorded only when the fork
reaches `.active`, so retrying the same config after a failed apply re-runs `apply`.
There is deliberately no `replace` / era-swap equivalent: cordis-rs fixes dependency edges for an era and needs a swap to
retarget them, whereas `Fork.resolve()` re-reads the edges on every reconcile, so a plain restart already retargets.
Dispose and load again for a fresh identity.

## Loader

`CordisLoader` (separate target, Foundation only) loads plugins from declarative JSON-configured entries. A `PluginRegistry`
maps a string resolve key to a plugin type plus a type-erased decode closure, so the plugin owns its `Config` type and the
registry owns decoding. A `LoadPlan` is an ordered list of entries (`key`, optional `name`, optional JSON `config`).
`plan.validate(against:)` collects every error (`LoaderError`: unknown key, duplicate name, config that fails to decode).
`ctx.load(plan, registry:)` validates first; an invalid plan loads nothing and every entry is reported failed. Otherwise entries
load in plan order and each `LoadOutcome` carries the status read once `ctx.plugin` returns (`pending`, `active` or `failed`:
plugins stay pending until their services exist). A failed entry does not stop the others. Strings never enter `CordisKernel`.

## Testing

`CordisTesting` (depends on `CordisKernel` only, never links `Testing` or `XCTest`) is for test targets, never production
code. It provides `ManualClock` (deterministic `Clock`), `settle(until:)` (bounded yields, returns whether the condition held)
and `withTestApp { ctx, events in … }`, which runs the body on a fresh root context, always disposes it (even if the body
throws) and returns `RecordedEvents` (`PluginFailed`, `PluginStatusChanged`, `ServiceChanged`, `TeardownFailed` in emission
order). The recorder is registered first, so listener teardown (reverse order) removes it last and it still sees
`TeardownFailed` raised during dispose, including by teardowns the body registered. The API is 0.x and experimental.

## Tests

`swift test`: `CordisKernelTests` covers scope, graph, lifecycle and cascade invariants; `CordisTests` covers `ServicePlugin` and timers; `CordisLoaderTests` covers the loader; `CordisTestingTests` covers the test-support module.
