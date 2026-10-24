import Testing
@testable import CordisKernel

@CordisActor
final class Probe {
    var log: [String] = []
}

enum ValueKey: ServiceKey { typealias Value = String }
struct Ping: Event {}

enum Provider: Plugin {
    static func apply(_ ctx: Context, config: (Probe, String)) async throws {
        let (probe, value) = config
        try await ctx.provide(ValueKey.self, value)
        probe.log.append("provide:\(value)")
        ctx.onDispose { probe.log.append("withdraw:\(value)") }
    }
}

enum Consumer: Plugin {
    static let inject = Inject(required: [ValueKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        let value = try ctx.require(ValueKey.self)
        config.log.append("start:\(value)")
        ctx.on(Ping.self) { _ in config.log.append("ping:\(value)") }
        ctx.onDispose { config.log.append("stop:\(value)") }
    }
}

enum Failing: Plugin {
    struct Boom: Error {}
    static func apply(_ ctx: Context, config: Probe) async throws {
        ctx.onDispose { config.log.append("rollback") }
        throw Boom()
    }
}

@CordisActor
@Suite
struct GraphTests {
    @Test
    func consumerWaitsForRequiredService() async {
        let app = Context.root(), probe = Probe()
        let consumer = await app.plugin(Consumer.self, probe)
        #expect(consumer.status == .pending)

        await app.plugin(Provider.self, (probe, "A"))
        #expect(consumer.status == .active)
        #expect(probe.log == ["start:A", "provide:A"])
    }

    @Test
    func hotSwapRestartsDependents() async {
        let app = Context.root(), probe = Probe()
        let provider = await app.plugin(Provider.self, (probe, "A"))
        await app.plugin(Consumer.self, probe)
        probe.log.removeAll()

        await provider.update((probe, "B"))
        #expect(probe.log == ["withdraw:A", "stop:A", "start:B", "provide:B"])
    }

    @Test
    func unloadRollsBackListeners() async {
        let app = Context.root(), probe = Probe()
        let provider = await app.plugin(Provider.self, (probe, "A"))
        let consumer = await app.plugin(Consumer.self, probe)

        await app.emit(Ping())
        await provider.dispose()
        await app.emit(Ping())

        #expect(consumer.status == .pending)
        #expect(probe.log.filter { $0.hasPrefix("ping") } == ["ping:A"])
    }

    @Test
    func isolationGivesEachRealmItsOwnInstance() async {
        let app = Context.root(), probe = Probe()
        let tenantA = app.isolate(ValueKey.self, label: "a")
        let tenantB = app.isolate(ValueKey.self, label: "b")

        await tenantA.plugin(Provider.self, (probe, "A"))
        let consumerB = await tenantB.plugin(Consumer.self, probe)
        #expect(consumerB.status == .pending) // A's value is invisible to B

        await tenantB.plugin(Provider.self, (probe, "B"))
        #expect(consumerB.status == .active)
        #expect(tenantA[ValueKey.self] == "A")
        #expect(tenantB[ValueKey.self] == "B")
        #expect(app[ValueKey.self] == nil)
    }

    @Test
    func conflictingProvidersAreRejected() async {
        let app = Context.root(), probe = Probe()
        await app.plugin(Provider.self, (probe, "A"))
        let second = await app.plugin(Provider.self, (probe, "B"))
        guard case .failed = second.status else {
            Issue.record("expected failure, got \(second.status)"); return
        }

        #expect(app[ValueKey.self] == "A")
    }

    @Test
    func failingPluginIsRolledBack() async {
        let app = Context.root(), probe = Probe()
        let reported = Probe()
        app.on(PluginFailed.self) { reported.log.append($0.plugin) }

        let handle = await app.plugin(Failing.self, probe)
        guard case .failed = handle.status else { Issue.record("expected failure"); return }

        #expect(probe.log == ["rollback"])
        #expect(reported.log == ["Failing"])
    }

    @Test
    func disposingRootTearsDownEverythingInReverse() async {
        let app = Context.root(), probe = Probe()
        await app.plugin(Provider.self, (probe, "A"))
        await app.plugin(Consumer.self, probe)
        probe.log.removeAll()

        await app.dispose()
        #expect(probe.log == ["stop:A", "withdraw:A"])
    }
}
