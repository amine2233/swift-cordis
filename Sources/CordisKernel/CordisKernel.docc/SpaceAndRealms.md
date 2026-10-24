# Space: services and realms

Typed service keys decide *what* a plugin depends on; realms decide *which instance* it sees.

## Service keys

A service is identified by a ``ServiceKey``, in the style of SwiftUI's `EnvironmentKey`. `Value` is usually a protocol,
so implementations can be hot-swapped.

```swift
enum DatabaseKey: ServiceKey { typealias Value = any Database }

extension Context {                      // Cordis-style mixin: ctx.database
    var database: (any Database)? { self[DatabaseKey.self] }
}
```

Plugins declare what they need with ``Inject``: `required` services keep the plugin pending until they exist;
`optional` ones let it start without them but restart when they change.

## Realms

A service instance lives at a ``Slot``: `(service, realm)`. By default every service is in the shared realm, so one
provider serves everyone. ``Context/isolate(_:label:)`` returns a child context where one key resolves in another realm:

```swift
let acme = app.isolate(DatabaseKey.self, label: "acme")
await acme.plugin(SQLitePlugin.self, "acme.db")   // visible only inside realm "acme"
```

- Same label: shared realm (every plugin loaded under `acme` sees the same database).
- No label: a private anonymous realm.
- Two *different* contexts cannot provide the same slot (see <doc:FailureModel>).
