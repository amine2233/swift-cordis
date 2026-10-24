import Testing
@testable import CordisKernel

struct TeardownBoom: Error, Equatable {
    let id: Int
}

enum FailingTeardownPlugin: Plugin {
    static func apply(_ ctx: Context, config: Probe) async throws {
        ctx.onDispose { config.log.append("ok") }
        ctx.onDispose { throw TeardownBoom(id: 1) }
    }
}

@CordisActor
@Suite
struct TeardownFailureTests {
    @Test
    func failingTeardownDoesNotStopLaterOnes() async {
        let probe = Probe()
        var reported: [TeardownBoom] = []
        let scope = Scope { error in
            if let boom = error as? TeardownBoom { reported.append(boom) }
        }
        scope.collect { probe.log.append("first") }
        scope.collect { throw TeardownBoom(id: 1) }
        scope.collect { probe.log.append("last") }
        scope.collect { throw TeardownBoom(id: 2) }
        await scope.dispose()
        #expect(probe.log == ["last", "first"])
        #expect(reported == [TeardownBoom(id: 2), TeardownBoom(id: 1)])
    }

    @Test
    func rootScopeEmitsTeardownFailedWithRootName() async {
        let app = Context.root()
        let probe = Probe()
        app
            .on(TeardownFailed.self) {
                probe.log.append("\($0.plugin):\(($0.error as? TeardownBoom)?.id ?? -1)")
            }
        app.onDispose { throw TeardownBoom(id: 7) }
        await app.dispose()
        #expect(probe.log == ["root:7"])
    }

    @Test
    func forkScopeEmitsTeardownFailedWithPluginName() async {
        let app = Context.root()
        let probe = Probe()
        app.on(TeardownFailed.self) { probe.log.append("\($0.plugin)") }
        await app.plugin(FailingTeardownPlugin.self, probe)
        await app.dispose()
        #expect(probe.log == [FailingTeardownPlugin.name, "ok"])
    }

    @Test
    func disposableCallReportsOnceAndStaysNonThrowing() async {
        var count = 0
        let scope = Scope { _ in count += 1 }
        let handle = scope.collect { throw TeardownBoom(id: 1) }
        await handle()
        await handle()
        #expect(count == 1)
        #expect(handle.isDisposed)
    }
}
