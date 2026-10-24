import Testing
@testable import CordisKernel

enum MidKey: ServiceKey { typealias Value = Int }
enum OtherKey: ServiceKey { typealias Value = String }

/// Requires `ValueKey`, provides `MidKey`: the middle link of an A → B → C chain.
enum Mid: Plugin {
    static let inject = Inject(required: [ValueKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        let value = try ctx.require(ValueKey.self)
        config.log.append("mid:\(value)")
        try await ctx.provide(MidKey.self, value.count)
    }
}

enum Leaf: Plugin {
    static let inject = Inject(required: [MidKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        try config.log.append("leaf:\(ctx.require(MidKey.self))")
        ctx.onDispose { config.log.append("leaf-stop") }
    }
}

enum OptionalConsumer: Plugin {
    static let inject = Inject(optional: [ValueKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        let value = ctx[ValueKey.self] ?? "none"
        config.log.append("start:\(value)")
    }
}

enum Parent: Plugin {
    static func apply(_ ctx: Context, config: Probe) async throws {
        await ctx.plugin(Consumer.self, config)
        ctx.onDispose { config.log.append("parent-stop") }
    }
}

enum Effecting: Plugin {
    static func apply(_ ctx: Context, config: Probe) async throws {
        try await ctx.effect {
            config.log.append("setup")
            return { config.log.append("teardown") }
        }
    }
}

@CordisActor
@Suite
struct LifecycleTests {
    @Test
    func optionalDependencyRestartsWhenItAppearsAndVanishes() async {
        let app = Context.root(), probe = Probe()
        let consumer = await app.plugin(OptionalConsumer.self, probe)
        #expect(consumer.status == .active)

        let provider = await app.plugin(Provider.self, (probe, "A"))
        await provider.dispose()

        #expect(probe.log.filter { $0.hasPrefix("start") } == ["start:none", "start:A", "start:none"])
    }

    @Test
    func cascadeGoesPendingAndComesBack() async {
        let app = Context.root(), probe = Probe()
        let leaf = await app.plugin(Leaf.self, probe)
        let mid = await app.plugin(Mid.self, probe)
        let provider = await app.plugin(Provider.self, (probe, "AB"))
        #expect(mid.status == .active)
        #expect(leaf.status == .active)

        await provider.dispose()
        #expect(mid.status == .pending)
        #expect(leaf.status == .pending)

        await app.plugin(Provider.self, (probe, "ABC"))
        #expect(leaf.status == .active)
        #expect(probe.log.contains("leaf:3"))
    }

    @Test
    func disposingParentDisposesSubtree() async {
        let app = Context.root(), probe = Probe()
        await app.plugin(Provider.self, (probe, "A"))
        let parent = await app.plugin(Parent.self, probe)
        probe.log.removeAll()

        await parent.dispose()
        #expect(probe.log.contains("parent-stop"))
        #expect(app.registry.listenerCount(for: Ping.self) == 0)
        #expect(parent.status == .disposed)
    }

    @Test
    func updatingPendingPluginDoesNotStartIt() async {
        let app = Context.root(), probe = Probe()
        let consumer = await app.plugin(Consumer.self, probe)
        await consumer.update(probe)
        #expect(consumer.status == .pending)
        #expect(probe.log.isEmpty)
    }

    @Test
    func unrelatedSlotChangeDoesNotRestart() async {
        let app = Context.root(), probe = Probe()
        await app.plugin(Provider.self, (probe, "A"))
        await app.plugin(Consumer.self, probe)
        probe.log.removeAll()

        try? await app.provide(OtherKey.self, "x")
        #expect(probe.log.isEmpty)
    }

    @Test
    func effectTeardownRunsExactlyOnce() async {
        let app = Context.root(), probe = Probe()
        let handle = await app.plugin(Effecting.self, probe)
        await handle.dispose()
        await handle.dispose()
        await app.dispose()
        #expect(probe.log == ["setup", "teardown"])
    }

    @Test
    func listenerAddedDuringDispatchMissesCurrentEvent() async {
        let app = Context.root()
        let counter = Probe()
        app.on(Ping.self) { _ in
            app.on(Ping.self) { _ in counter.log.append("late") }
        }
        await app.emit(Ping())
        #expect(counter.log.isEmpty)
        await app.emit(Ping())
        #expect(counter.log == ["late"])
    }

    @Test
    func providingAfterDisposeThrows() async {
        let app = Context.root()
        await app.dispose()
        await #expect(throws: CordisError.self) {
            try await app.provide(OtherKey.self, "x")
        }
    }

    @Test
    func requireThrowsWhenMissing() {
        let app = Context.root()
        #expect(throws: CordisError.self) { try app.require(OtherKey.self) }
    }
}

@CordisActor
@Suite
struct ScopeTests {
    @Test
    func disposeRunsTeardownsInLIFOOrder() async {
        let scope = Scope(), probe = Probe()
        scope.collect { probe.log.append("1") }
        scope.collect { probe.log.append("2") }
        scope.collect { probe.log.append("3") }
        await scope.dispose()
        #expect(probe.log == ["3", "2", "1"])
        #expect(scope.isDisposed)
    }

    @Test
    func disposableIsIdempotent() async {
        let scope = Scope(), probe = Probe()
        let handle = scope.collect { probe.log.append("x") }
        await handle()
        await handle()
        await scope.dispose()
        #expect(probe.log == ["x"])
        #expect(handle.isDisposed)
    }

    @Test
    func disposeIsIdempotent() async {
        let scope = Scope(), probe = Probe()
        scope.collect { probe.log.append("x") }
        await scope.dispose()
        await scope.dispose()
        #expect(probe.log == ["x"])
    }
}
