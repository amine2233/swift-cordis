import CordisKernel
import CordisTesting
import Testing

struct Boom: Error {}

enum FailingPlugin: Plugin {
    static func apply(_ ctx: Context, config _: Void) async throws {
        throw Boom()
    }
}

enum WidgetKey: ServiceKey { typealias Value = Int }

enum ConsumerPlugin: Plugin {
    static let inject = Inject(required: [WidgetKey.self])

    static func apply(_ ctx: Context, config _: Void) async throws {}
}

@CordisActor
@Suite
struct TestAppTests {
    @Test
    func throwingBodyStillDisposes() async {
        var disposed = false
        do {
            try await withTestApp { ctx, _ in
                ctx.onDispose { disposed = true }
                throw Boom()
            }
            Issue.record("expected throw")
        } catch {
            #expect(error is Boom)
        }
        #expect(disposed)
    }

    @Test
    func normalBodyDisposes() async {
        var disposed = false
        await withTestApp { ctx, _ in ctx.onDispose { disposed = true } }
        #expect(disposed)
    }

    @Test
    func recordsLifecycleEventsInOrder() async throws {
        let events = try await withTestApp { ctx, recorded in
            let handle = await ctx.plugin(ConsumerPlugin.self)
            #expect(handle.status == .pending)
            try await ctx.provide(WidgetKey.self, 1)
            #expect(handle.status == .active)
            #expect(!recorded.all.isEmpty)
        }
        let statuses = events.ofType(PluginStatusChanged.self).map(\.status)
        #expect(Array(statuses.prefix(2)) == [.loading, .active])
        let firstChange = events.all.firstIndex { $0 is ServiceChanged }
        let firstActive = events.all.firstIndex {
            ($0 as? PluginStatusChanged)?.status == .active
        }
        #expect(firstChange != nil)
        #expect(firstChange.map { index in firstActive.map { index < $0 } ?? false } == true)
    }

    @Test
    func failingPluginAppearsInFailures() async {
        let events = await withTestApp { ctx, _ in
            await ctx.plugin(FailingPlugin.self)
        }
        #expect(events.failures.count == 1)
        let failure = events.ofType(PluginFailed.self).first?.error
        #expect(failure is Boom)
    }

    @Test
    func teardownFailureRaisedByBodyIsVisibleAfterDispose() async {
        let events = await withTestApp { ctx, _ in
            ctx.onDispose { throw Boom() }
        }
        let failures = events.ofType(TeardownFailed.self)
        #expect(failures.count == 1)
        #expect(failures.first?.plugin == "root")
        let error = failures.first?.error
        #expect(error is Boom)
        #expect(events.failures.count == 1)
    }
}
