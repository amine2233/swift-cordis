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

## Space

A `Slot` is `(service, realm)`. `ctx.isolate(Key.self, label:)` returns a child context resolving that key in another realm.
Same label = shared realm, no label = private anonymous realm.

## Failure model

`apply` throwing rolls back the fork's scope, sets `.failed`, and emits `PluginFailed`. The rest of the graph keeps running.
Two different contexts providing the same slot raise `CordisError.serviceConflict`; the second plugin fails.

## Snapshot

`ctx.snapshot()` (synchronous, on `@CordisActor`) returns an immutable `RuntimeSnapshot` copy of the graph:
`plugins: [PluginInfo]` (opaque `PluginID`, name, status, parent) and `slots: [SlotInfo]` (service, realm, providing `PluginID?`, generation).
Plugins are listed in registration order, slots in provision order. Disposed plugins are unregistered, so they are not listed.
It carries no control capability and no observation stream (deferred, Proposal 0004). The record shapes are provisional.

## Known limitation

`Scope.collect` on an already-disposed scope runs the teardown in a `Task` (the signature is synchronous),
so that one path is not ordered with respect to other events.

## Tests

`swift test`: `CordisKernelTests` covers scope, graph, lifecycle and cascade invariants; `CordisTests` covers `ServicePlugin`.
