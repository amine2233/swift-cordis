# Time: scopes and teardown

Every side effect registered through a ``Context`` is undone automatically when its plugin stops.

## Overview

Each running plugin owns a ``Scope``. Anything you register through its context (``Context/provide(_:_:)``,
``Context/on(_:_:)``, ``Context/effect(_:)``, ``Context/onDispose(_:)``, ``Context/plugin(_:_:)``) adds a teardown to
that scope. When the plugin is disposed, reloaded with new config, or loses a required service, the scope disposes
its teardowns in **reverse order of registration**, like `defer`.

```swift
enum Heartbeat: Plugin {
    static func apply(_ ctx: Context, config: Duration) async throws {
        try await ctx.effect {
            let timer = Timer.start(every: config)
            return { timer.stop() }          // runs on dispose / reload
        }
    }
}
```

You never write the matching "unregister": there is no `removeObserver` to forget.

### Guarantees

- Teardowns run LIFO.
- A ``Disposable`` is single-use: calling it twice runs the teardown once.
- Disposing a parent plugin disposes its sub-plugins first.
- Disposing a scope twice is a no-op.

> Important: `apply` must only *register* side effects through `ctx`. Work done behind the context's back is not
> rolled back.
