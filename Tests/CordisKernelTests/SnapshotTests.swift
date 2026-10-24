import Testing
@testable import CordisKernel

enum SnapshotKey: ServiceKey { typealias Value = Int }
enum SnapshotOtherKey: ServiceKey { typealias Value = Int }

enum SnapshotProvider: Plugin {
    static func apply(_ ctx: Context, config: Void) async throws {
        try await ctx.provide(SnapshotKey.self, 1)
    }
}

enum SnapshotSecondProvider: Plugin {
    static func apply(_ ctx: Context, config: Void) async throws {
        try await ctx.provide(SnapshotOtherKey.self, 2)
    }
}

enum SnapshotWaiting: Plugin {
    static let inject = Inject(required: [SnapshotKey.self])
    static func apply(_ ctx: Context, config: Void) async throws {}
}

enum SnapshotFailing: Plugin {
    struct Boom: Error {}
    static func apply(_ ctx: Context, config: Void) async throws {
        throw Boom()
    }
}

enum SnapshotParent: Plugin {
    static func apply(_ ctx: Context, config: Void) async throws {
        await ctx.plugin(SnapshotWaiting.self)
    }
}

@CordisActor
@Suite
struct SnapshotTests {
    @Test
    func emptyRootHasEmptySnapshot() {
        let snapshot = Context.root().snapshot()
        #expect(snapshot.plugins.isEmpty)
        #expect(snapshot.slots.isEmpty)
    }

    @Test
    func reportsPendingActiveAndFailedStatuses() async {
        let app = Context.root()
        await app.plugin(SnapshotWaiting.self)
        await app.plugin(SnapshotFailing.self)
        #expect(app.snapshot().plugins.map(\.status) == [
            .pending,
            .failed(String(describing: SnapshotFailing.Boom()))
        ])

        await app.plugin(SnapshotProvider.self)
        #expect(app.snapshot().plugins.map(\.status) == [
            .active,
            .failed(String(describing: SnapshotFailing.Boom())),
            .active
        ])
    }

    @Test
    func disposedPluginsAreNotListed() async {
        let app = Context.root()
        let handle = await app.plugin(SnapshotProvider.self)
        await handle.dispose()
        #expect(handle.status == .disposed)
        #expect(app.snapshot().plugins.isEmpty)
    }

    @Test
    func slotAppearsAfterProvideAndDisappearsAfterDispose() async {
        let app = Context.root()
        let handle = await app.plugin(SnapshotProvider.self)
        let snapshot = app.snapshot()
        #expect(snapshot.slots.count == 1)
        #expect(snapshot.slots[0].service == SnapshotKey.id.description)
        #expect(snapshot.slots[0].realm == Slot.sharedRealm)
        #expect(snapshot.slots[0].provider == snapshot.plugins[0].id)

        await handle.dispose()
        #expect(app.snapshot().slots.isEmpty)
    }

    @Test
    func rootProvidedSlotHasNoProvider() async throws {
        let app = Context.root()
        try await app.provide(SnapshotKey.self, 1)
        #expect(app.snapshot().slots.map(\.provider) == [nil])
    }

    @Test
    func isolatedContextsShowTheirRealms() async throws {
        let app = Context.root()
        try await app.provide(SnapshotKey.self, 1)
        try await app.isolate(SnapshotKey.self, label: "tenant").provide(SnapshotKey.self, 2)
        #expect(app.snapshot().slots.map(\.realm) == [Slot.sharedRealm, "tenant"])
    }

    @Test
    func parentLinksFollowComposition() async {
        let app = Context.root()
        await app.plugin(SnapshotParent.self)
        let plugins = app.snapshot().plugins
        #expect(plugins.count == 2)
        #expect(plugins[0].parent == nil)
        #expect(plugins[1].parent == plugins[0].id)
    }

    @Test
    func snapshotIsACopy() async {
        let app = Context.root()
        let before = app.snapshot()
        await app.plugin(SnapshotProvider.self)
        #expect(before.plugins.isEmpty)
        #expect(before.slots.isEmpty)
        #expect(app.snapshot().plugins.count == 1)
    }

    @Test
    func orderingIsRegistrationOrderForPluginsAndProvisionOrderForSlots() async {
        let app = Context.root()
        for _ in 0 ..< 5 {
            await app.plugin(SnapshotSecondProvider.self)
            await app.plugin(SnapshotWaiting.self)
        }
        let names = app.snapshot().plugins.map(\.name)
        #expect(names == Array(repeating: [SnapshotSecondProvider.name, SnapshotWaiting.name], count: 5)
            .flatMap { $0 })

        await app.plugin(SnapshotProvider.self)
        let snapshot = app.snapshot()
        let generations = snapshot.slots.map(\.generation)
        #expect(snapshot.slots.count == 2)
        #expect(generations == generations.sorted())
        #expect(snapshot.slots.last?.provider == snapshot.plugins.last?.id)
    }
}
