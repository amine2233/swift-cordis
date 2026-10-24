# Failure model

Failures stay local: one broken plugin does not take the graph down.

## Overview

- If `apply` throws, the fork's scope is rolled back, its status becomes ``Fork/Status/failed(_:)`` and a
  ``PluginFailed`` event is emitted on the parent context. Everything else keeps running.
- A ``Disposer`` may throw. Every teardown of a scope still runs (reverse order), and each thrown error is emitted
  once as a ``TeardownFailed`` event naming the owning context.
- Providing a slot already owned by a different context throws ``CordisError/serviceConflict(_:existingOwner:)``.
  The second plugin fails and the first value is kept.
- ``Context/require(_:)`` throws ``CordisError/missingService(_:)`` when a service is not visible from that context.
- Providing from a disposed context throws ``CordisError/disposed``.

```swift
app.on(PluginFailed.self) { event in
    print("\(event.plugin) failed: \(event.error)")
}
```
