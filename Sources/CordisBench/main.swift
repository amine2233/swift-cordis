import Cordis

enum ValueKey: ServiceKey { typealias Value = Int }

enum NoopPlugin: Plugin {
    static func apply(_ ctx: Context, config: Void) async throws {}
}

enum DependentPlugin: Plugin {
    static let inject = Inject(required: [ValueKey.self])

    static func apply(_ ctx: Context, config: Void) async throws {
        _ = try ctx.require(ValueKey.self)
    }
}

enum ProviderPlugin: Plugin {
    static func apply(_ ctx: Context, config: Int) async throws {
        try await ctx.provide(ValueKey.self, config)
    }
}

@CordisActor
func loadPlugins(_ count: Int) async -> Int {
    let app = Context.root()
    let elapsed = await ContinuousClock().measure {
        for _ in 0 ..< count {
            await app.plugin(NoopPlugin.self)
        }
    }
    await app.dispose()
    return nanoseconds(elapsed)
}

@CordisActor
func provideAffectingDependents(_ count: Int) async throws -> Int {
    let app = Context.root()
    for _ in 0 ..< count {
        await app.plugin(DependentPlugin.self)
    }
    let elapsed = try await ContinuousClock().measure {
        try await app.provide(ValueKey.self, 0)
    }
    await app.dispose()
    return nanoseconds(elapsed)
}

@CordisActor
func updateWithDependents(_ count: Int) async -> Int {
    let app = Context.root()
    let provider = await app.plugin(ProviderPlugin.self, 0)
    for _ in 0 ..< count {
        await app.plugin(DependentPlugin.self)
    }
    let elapsed = await ContinuousClock().measure {
        await provider.update(1)
    }
    await app.dispose()
    return nanoseconds(elapsed)
}

func nanoseconds(_ duration: Duration) -> Int {
    let parts = duration.components
    return Int(parts.seconds) * 1_000_000_000 + Int(parts.attoseconds / 1_000_000_000)
}

@CordisActor
func runBench(sizes: [Int]) async throws {
    for count in sizes {
        await print("load,\(count),\(loadPlugins(count) / count)")
        try await print("provide,\(count),\(provideAffectingDependents(count) / count)")
        await print("update,\(count),\(updateWithDependents(count) / count)")
    }
}

let requested = CommandLine.arguments.dropFirst().compactMap { Int($0) }.filter { $0 > 0 }
try await runBench(sizes: requested.isEmpty ? [10, 100, 1_000] : requested)
