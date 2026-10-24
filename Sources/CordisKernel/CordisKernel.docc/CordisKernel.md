# ``CordisKernel``

The plugin kernel: scopes, services, forks and contexts. No sugar.

> Note: Unofficial Swift port of [Cordis](https://github.com/cordiverse/cordis).

## Overview

In Cordis **everything is a plugin**. A plugin never touches global state: it receives a ``Context`` and registers
everything it does through it (services, event listeners, effects, sub-plugins). Because the context records those
registrations, the kernel can undo them all, in reverse order, when the plugin stops.

That gives plugins composability on three axes:

- **Time**: what happens on load, reload and unload. See <doc:TimeAndScopes>.
- **Space**: which instance of a service a plugin sees. See <doc:SpaceAndRealms>.
- **Reactivity**: what happens when a dependency appears, changes or vanishes. See <doc:Reactivity>.

All graph mutations run on the single global actor ``CordisActor``.

## Topics

### Concepts

- <doc:TimeAndScopes>
- <doc:SpaceAndRealms>
- <doc:Reactivity>
- <doc:FailureModel>

### Plugins

- ``Plugin``
- ``PluginHandle``
- ``Fork``
- ``Inject``

### Context

- ``Context``

### Services

- ``ServiceKey``
- ``ServiceID``
- ``Slot``

### Lifetime

- ``Scope``
- ``Disposable``
- ``Disposer``
- ``CordisActor``

### Events and errors

- ``Event``
- ``ServiceChanged``
- ``PluginStatusChanged``
- ``PluginFailed``
- ``CordisError``
