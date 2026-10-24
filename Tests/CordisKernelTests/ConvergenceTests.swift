import Testing
@testable import CordisKernel

final class Counter {
    var limit = 0
}

enum CounterKey: ServiceKey { typealias Value = Counter }

enum CounterConsumer: Plugin {
    static let inject = Inject(required: [CounterKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        try config.log.append("start:\(ctx.require(CounterKey.self).limit)")
    }
}

@CordisActor
@Suite
struct ConvergenceTests {
    @Test
    func updateMutatesPublishedValueWithoutRestartingDependents() async throws {
        let app = Context.root(), probe = Probe()
        let events = Probe()
        app.on(ServiceChanged.self) { _ in events.log.append("changed") }
        try await app.provide(CounterKey.self, Counter())
        await app.plugin(CounterConsumer.self, probe)
        events.log.removeAll()

        try await app.update(CounterKey.self) { (value: inout Counter) in value.limit = 10 }

        #expect(app[CounterKey.self]?.limit == 10)
        #expect(probe.log == ["start:0"])
        #expect(events.log.isEmpty)
    }

    @Test
    func updateKeepsOccurrenceAndGeneration() async throws {
        let app = Context.root()
        try await app.provide(CounterKey.self, Counter())
        let before = app.snapshot().slots
        try await app.update(CounterKey.self) { (value: inout Counter) in value.limit = 1 }
        #expect(app.snapshot().slots.map(\.generation) == before.map(\.generation))
    }

    @Test
    func updateThrowsWhenSlotIsNotProvided() async {
        let app = Context.root()
        await #expect(throws: CordisError.self) {
            try await app.update(CounterKey.self) { (value: inout Counter) in value.limit = 1 }
        }
    }

    @Test
    func updateThrowsWhenAnotherContextPublishedTheSlot() async throws {
        let app = Context.root()
        let other = Context.root()
        try await other.provide(CounterKey.self, Counter())
        await #expect(throws: CordisError.self) {
            try await app.update(CounterKey.self) { (value: inout Counter) in value.limit = 1 }
        }
    }

    @Test
    func republishingIsANewOccurrenceAndRestartsDependents() async throws {
        let app = Context.root(), probe = Probe()
        try await app.provide(CounterKey.self, Counter())
        await app.plugin(CounterConsumer.self, probe)

        try await app.provide(CounterKey.self, Counter())

        #expect(probe.log == ["start:0", "start:0"])
    }
}
