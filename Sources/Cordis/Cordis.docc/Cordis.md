# ``Cordis``

Everything is a plugin. Compose them over time, space and dependencies.

> Note: Unofficial Swift port of [Cordis](https://github.com/cordiverse/cordis). Not affiliated with its authors.

## Overview

`Cordis` is the module you normally import. It re-exports `CordisKernel` (``Context``, ``Plugin``, ``ServiceKey``, ``Inject``…)
and adds ``ServicePlugin``, sugar for plugins whose only job is to provide one service.

Read the concepts in the `CordisKernel` documentation: time (scopes), space (realms) and reactivity (forks).

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Examples>

### Sugar

- ``ServicePlugin``
