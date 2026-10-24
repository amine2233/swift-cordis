# swift-cordis

> **Unofficial** Swift 6 port of the [Cordis](https://github.com/cordiverse/cordis) principle
> (the plugin kernel behind Koishi). Not affiliated with the Cordis authors.

Cordis' idea: **everything is a plugin**, and plugins compose along two axes.

| Axis | Question | Mechanism |
|---|---|---|
| Time | What happens when a plugin loads / reloads / unloads? | `Scope`: every side effect registered through a `Context` is undone automatically, LIFO |
| Space | Which instance of a service does a plugin see? | `Slot = (service, realm)` and `ctx.isolate(Key.self, label:)` |
| Reactivity | What if a dependency appears / changes / disappears? | `Fork`: dependents go pending → active, restart, or fall back to pending |

## Modules

- `CordisKernel`: `Scope`, `Fork`, `Registry`, `Context`, `ServiceKey`, `Inject`, events. No sugar.
- `Cordis`: re-exports the kernel and adds `ServicePlugin`.

## Quickstart

```swift
import Cordis

enum GreetingKey: ServiceKey { typealias Value = String }

enum GreetingPlugin: ServicePlugin {
    typealias Key = GreetingKey
    typealias Config = String
    static func make(_ ctx: Context, config: String) async throws -> String { "hello \(config)" }
}

enum Printer: Plugin {
    static let inject = Inject(required: [GreetingKey.self])
    static func apply(_ ctx: Context, config: Void) async throws {
        print(try ctx.require(GreetingKey.self))
    }
}

@CordisActor func run() async {
    let app = Context.root()
    await app.plugin(Printer.self)                      // pending: no greeting yet
    let greeting = await app.plugin(GreetingPlugin.self, "world")  // Printer starts
    await greeting.update("swift")                      // hot swap: Printer restarts
    await greeting.dispose()                            // Printer back to pending
}
```

Run `swift run cordis-demo` for a six-scenario walkthrough.

Documentation: DocC catalogs in `Sources/Cordis/Cordis.docc` (getting started, examples) and
`Sources/CordisKernel/CordisKernel.docc` (concepts). Internals: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Cordis → Swift

| Cordis | Swift |
|---|---|
| `ctx.plugin(fn, config)` | `await ctx.plugin(P.self, config)` → `PluginHandle<P>` |
| `inject: [...]` | `static let inject = Inject(required:, optional:)` |
| `ctx.provide('db')` | `try await ctx.provide(Key.self, value)` |
| `ctx.db` | `extension Context { var db: ... { self[DBKey.self] } }` |
| `ctx.on` / `ctx.emit` | `ctx.on(E.self) { }` / `await ctx.emit(E())` |
| `ctx.effect` | `try await ctx.effect { …; return { teardown } }` |
| `ctx.on('dispose')` | `ctx.onDispose { }` |
| `ctx.isolate('db')` | `ctx.isolate(Key.self, label:)` |
| `fork.update` / `fork.dispose` | `handle.update(config)` / `handle.dispose()` |
