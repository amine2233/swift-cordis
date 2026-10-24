# Examples

Recipes covering each part of the model. `Sources/CordisDemo/main.swift` runs all of them.

## A domain service on top of another

```swift
enum UserRepositoryPlugin: Plugin {
    static let inject = Inject(required: [DatabaseKey.self], optional: [LoggerKey.self])

    static func apply(_ ctx: Context, config: Void) async throws {
        let db = try ctx.require(DatabaseKey.self)
        try await ctx.provide(UserRepositoryKey.self, UserRepository(db: db))
        ctx.logger?.info("UserRepository ready on '\(db.label)'")
    }
}
```

Swapping the database restarts the repository, and everything that injects the repository, automatically.

## A feature reacting to events

```swift
struct UserSignedUp: Event { let name: String }

enum WelcomeFeature: Plugin {
    static let inject = Inject(required: [UserRepositoryKey.self])

    static func apply(_ ctx: Context, config: Void) async throws {
        let users = try ctx.require(UserRepositoryKey.self)
        ctx.on(UserSignedUp.self) { event in users.create(event.name) }
    }
}

await app.emit(UserSignedUp(name: "Amine"))
```

The listener disappears with the plugin: after the repository is unplugged, `emit` reaches nobody.

## Hot swap and unplug

```swift
let db = await app.plugin(InMemoryDatabasePlugin.self, "sqlite")
await db.update("postgres")   // dependents: stop, start again on the new instance
await db.dispose()            // dependents: back to .pending
```

## One database per tenant

```swift
for tenant in ["acme", "globex"] {
    let scoped = app
        .isolate(DatabaseKey.self, label: tenant)
        .isolate(UserRepositoryKey.self, label: tenant)
    await scoped.plugin(InMemoryDatabasePlugin.self, "db-\(tenant)")
    await scoped.plugin(UserRepositoryPlugin.self)
}
```

The same plugins run twice, each wired to its tenant's database.

## Sub-plugins

```swift
enum Feature: Plugin {
    static func apply(_ ctx: Context, config: Void) async throws {
        await ctx.plugin(WelcomeFeature.self)   // lifetime bound to Feature
    }
}
```

Disposing `Feature` disposes `WelcomeFeature` with it.

## Observing the graph

```swift
app.on(PluginStatusChanged.self) { print("\($0.plugin) → \($0.status)") }
app.on(ServiceChanged.self) { print("\($0.slot) available: \($0.isAvailable)") }
```
