import Testing
@testable import CordisKernel

enum WrappedKey: ServiceKey { typealias Value = String }

enum WrappedProvider: Plugin {
    static func apply(_ ctx: Context, config: String) async throws {
        try await ctx.provide(WrappedKey.self, config)
    }
}

enum WrappedConsumer: Plugin {
    static let inject = Inject(required: [WrappedKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        config.log.append("saw:\(try ctx.require(WrappedKey.self))")
    }
}

@CordisActor
@Suite
struct InterceptTests {
    @Test
    func singleLayerWrapsProvidedValue() async throws {
        let app = Context.root()
        let traced = app.intercept(WrappedKey.self) { "traced(\($0))" }
        try await traced.provide(WrappedKey.self, "db")
        #expect(app[WrappedKey.self] == "traced(db)")
    }

    @Test
    func firstRegisteredLayerIsOutermost() async throws {
        let app = Context.root()
        let layered = app
            .intercept(WrappedKey.self) { "outer(\($0))" }
            .intercept(WrappedKey.self) { "inner(\($0))" }
        try await layered.provide(WrappedKey.self, "db")
        #expect(app[WrappedKey.self] == "outer(inner(db))")
    }

    @Test
    func layersAreInheritedByIsolatedContexts() async throws {
        let app = Context.root()
        let isolated = app.intercept(WrappedKey.self) { "L(\($0))" }.isolate(WrappedKey.self, label: "t")
        try await isolated.provide(WrappedKey.self, "db")
        #expect(isolated[WrappedKey.self] == "L(db)")
    }

    @Test
    func layersAreInheritedByLoadedPlugins() async {
        let app = Context.root()
        let traced = app.intercept(WrappedKey.self) { "L(\($0))" }
        await traced.plugin(WrappedProvider.self, "db")
        #expect(app[WrappedKey.self] == "L(db)")
    }

    @Test
    func siblingContextIsUnaffected() async throws {
        let app = Context.root()
        _ = app.intercept(WrappedKey.self) { "L(\($0))" }
        try await app.provide(WrappedKey.self, "db")
        #expect(app[WrappedKey.self] == "db")
    }

    @Test
    func layerIsNotAppliedRetroactively() async throws {
        let app = Context.root()
        try await app.provide(WrappedKey.self, "db")
        let traced = app.intercept(WrappedKey.self) { "L(\($0))" }
        #expect(app[WrappedKey.self] == "db")
        #expect(traced[WrappedKey.self] == "db")
    }

    @Test
    func dependentsReceiveWrappedValueWithoutExtraRestart() async {
        let app = Context.root(), probe = Probe()
        let consumer = await app.plugin(WrappedConsumer.self, probe)
        await app.intercept(WrappedKey.self) { "L(\($0))" }.plugin(WrappedProvider.self, "db")
        #expect(consumer.status == .active)
        #expect(probe.log == ["saw:L(db)"])
    }

    @Test
    func conflictBehaviourIsUnchanged() async throws {
        let app = Context.root()
        try await app.provide(WrappedKey.self, "a")
        let other = app.intercept(WrappedKey.self) { "L(\($0))" }
        await #expect(throws: CordisError.self) {
            try await other.provide(WrappedKey.self, "b")
        }
        #expect(app[WrappedKey.self] == "a")
    }
}
