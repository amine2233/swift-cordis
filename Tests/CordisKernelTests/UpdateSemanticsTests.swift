import Testing
@testable import CordisKernel

struct BadConfig: Error {}

enum Equal: Plugin {
    static func apply(_ ctx: Context, config: String) async throws {
        ctx.onDispose { Recorder.log.append("stop:\(config)") }
        Recorder.log.append("start:\(config)")
    }
}

enum FailsOnBad: Plugin {
    static func apply(_ ctx: Context, config: String) async throws {
        Recorder.log.append("apply:\(config)")
        if config == "bad" { throw BadConfig() }
    }
}

enum Opaque: Plugin {
    static func apply(_ ctx: Context, config: Probe) async throws {
        config.log.append("apply")
    }
}

enum Dependent: Plugin {
    static let inject = Inject(required: [ValueKey.self])
    static func apply(_ ctx: Context, config: Probe) async throws {
        config.log.append("dependent")
    }
}

enum ValueProvider: Plugin {
    static func apply(_ ctx: Context, config: String) async throws {
        try await ctx.provide(ValueKey.self, config)
    }
}

enum Recorder {
    @CordisActor static var log: [String] = []
}

@CordisActor
@Suite(.serialized)
struct UpdateSemanticsTests {
    init() {
        Recorder.log = []
    }

    @Test
    func equalConfigOnActivePluginIsNoOp() async {
        let app = Context.root()
        let handle = await app.plugin(Equal.self, "a")
        Recorder.log.removeAll()

        await handle.update("a")
        #expect(Recorder.log.isEmpty)
        #expect(handle.status == .active)
    }

    @Test
    func equalConfigDoesNotRestartDependents() async {
        let app = Context.root(), probe = Probe()
        let provider = await app.plugin(ValueProvider.self, "A")
        await app.plugin(Dependent.self, probe)
        probe.log.removeAll()

        await provider.update("A")
        #expect(probe.log.isEmpty)

        await provider.update("B")
        #expect(probe.log == ["dependent"])
    }

    @Test
    func differentConfigStillRestarts() async {
        let app = Context.root()
        let handle = await app.plugin(Equal.self, "a")
        Recorder.log.removeAll()

        await handle.update("b")
        #expect(Recorder.log == ["stop:a", "start:b"])
    }

    @Test
    func retryingSameConfigAfterFailedApplyReRunsApply() async {
        let app = Context.root()
        let handle = await app.plugin(FailsOnBad.self, "ok")
        await handle.update("bad")
        Recorder.log.removeAll()

        await handle.update("bad")
        #expect(Recorder.log == ["apply:bad"])
    }

    @Test
    func nonEquatableConfigStillRestarts() async {
        let app = Context.root(), probe = Probe()
        let handle = await app.plugin(Opaque.self, probe)
        probe.log.removeAll()

        await handle.update(probe)
        #expect(probe.log == ["apply"])
    }

    @Test
    func updateReportsUnchangedForEqualConfigAndAppliedOtherwise() async {
        let app = Context.root()
        let handle = await app.plugin(Equal.self, "a")

        guard case .unchanged = await handle.update("a") else {
            Issue.record("expected .unchanged")
            return
        }
        guard case .applied = await handle.update("b") else {
            Issue.record("expected .applied")
            return
        }
    }
}
