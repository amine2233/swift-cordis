import Testing
@testable import CordisKernel

enum ShapeError: Error, Equatable { case empty }

enum ValidatedProvider: Plugin {
    static func validate(config: (Probe, String)) throws {
        guard !config.1.isEmpty else { throw ShapeError.empty }
    }

    static func apply(_ ctx: Context, config: (Probe, String)) async throws {
        let (probe, value) = config
        try await ctx.provide(ValueKey.self, value)
        probe.log.append("provide:\(value)")
        ctx.onDispose { probe.log.append("withdraw:\(value)") }
    }
}

enum ApplyFailsAfterValidate: Plugin {
    struct Boom: Error {}
    static func validate(config: Bool) throws {}
    static func apply(_ ctx: Context, config: Bool) async throws {
        if config { throw Boom() }
    }
}

@CordisActor
@Suite
struct ValidateTests {
    @Test
    func rejectedConfigChangesNothing() async {
        let app = Context.root(), probe = Probe()
        let provider = await app.plugin(ValidatedProvider.self, (probe, "A"))
        await app.plugin(Consumer.self, probe)
        probe.log.removeAll()

        let outcome = await provider.update((probe, ""))

        guard case let .rejected(error) = outcome else { Issue.record("expected rejection"); return }

        #expect(error as? ShapeError == .empty)
        #expect(probe.log.isEmpty)
        #expect(provider.status == .active)
        #expect(app[ValueKey.self] == "A")
    }

    @Test
    func acceptedConfigApplies() async {
        let app = Context.root(), probe = Probe()
        let provider = await app.plugin(ValidatedProvider.self, (probe, "A"))

        let outcome = await provider.update((probe, "B"))

        guard case .applied = outcome else { Issue.record("expected applied"); return }

        #expect(app[ValueKey.self] == "B")
    }

    @Test
    func defaultValidateAccepts() async {
        let app = Context.root(), probe = Probe()
        let provider = await app.plugin(Provider.self, (probe, "A"))

        let outcome = await provider.update((probe, "B"))

        guard case .applied = outcome else { Issue.record("expected applied"); return }
    }

    @Test
    func applyFailureAfterValidateStillFails() async {
        let app = Context.root()
        let handle = await app.plugin(ApplyFailsAfterValidate.self, false)

        let outcome = await handle.update(true)

        guard case .applied = outcome else { Issue.record("expected applied"); return }
        guard case .failed = handle.status else { Issue.record("expected failed"); return }
    }
}
