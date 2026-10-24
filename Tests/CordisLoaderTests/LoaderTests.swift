import CordisLoader
import Foundation
import Testing

enum BaseKey: ServiceKey { typealias Value = Int }
enum DerivedKey: ServiceKey { typealias Value = Int }

struct BaseConfig: Decodable, Sendable {
    let value: Int
}

enum BasePlugin: Plugin {
    static func apply(_ ctx: Context, config: BaseConfig) async throws {
        try await ctx.provide(BaseKey.self, config.value)
    }
}

enum DerivedPlugin: Plugin {
    static let inject = Inject(required: [BaseKey.self])
    static func apply(_ ctx: Context, config _: Void) async throws {
        try await ctx.provide(DerivedKey.self, ctx.require(BaseKey.self) + 1)
    }
}

enum BrokenPlugin: Plugin {
    struct Failure: Error {}
    static func apply(_: Context, config _: Void) async throws {
        throw Failure()
    }
}

func json(_ text: String) -> Data {
    Data(text.utf8)
}

@CordisActor
func makeRegistry() -> PluginRegistry {
    var registry = PluginRegistry()
    registry.register(BasePlugin.self, key: "base")
    registry.register(DerivedPlugin.self, key: "derived")
    registry.register(BrokenPlugin.self, key: "broken")
    return registry
}

@CordisActor
@Suite
struct LoaderTests {
    @Test
    func validationReportsUnknownKey() {
        let plan = LoadPlan(entries: [.init(key: "nope")])
        #expect(plan.validate(against: makeRegistry()) == [.unknownKey("nope", entry: 0)])
    }

    @Test
    func validationReportsDuplicateName() {
        let plan = LoadPlan(entries: [
            .init(key: "derived", name: "a"),
            .init(key: "broken", name: "a")
        ])
        #expect(plan.validate(against: makeRegistry()) == [.duplicateName("a", entry: 1)])
    }

    @Test
    func validationReportsConfigDecodeFailure() {
        let plan = LoadPlan(entries: [.init(key: "base", config: json(#"{"value":"x"}"#))])
        let errors = plan.validate(against: makeRegistry())
        #expect(errors.count == 1)
        guard case .invalidConfig("base", entry: 0, _)? = errors.first else {
            Issue.record("expected invalidConfig, got \(errors)")
            return
        }
    }

    @Test
    func validationReportsMissingConfig() {
        let plan = LoadPlan(entries: [.init(key: "base")])
        #expect(plan.validate(against: makeRegistry()).count == 1)
    }

    @Test
    func validationCollectsEveryError() {
        let plan = LoadPlan(entries: [
            .init(key: "nope"),
            .init(key: "derived", name: "a"),
            .init(key: "derived", name: "a"),
            .init(key: "base", config: json("{}"))
        ])
        #expect(plan.validate(against: makeRegistry()).count == 3)
    }

    @Test
    func invalidPlanLoadsNothing() async {
        let app = Context.root()
        let plan = LoadPlan(entries: [.init(key: "broken"), .init(key: "nope")])
        let outcomes = await app.load(plan, registry: makeRegistry())
        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy { if case .failed = $0.status { true } else { false } })
        #expect(app.snapshot().plugins.isEmpty)
    }

    @Test
    func dependencyChainDeclaredOutOfOrder() async {
        let app = Context.root()
        let plan = LoadPlan(entries: [
            .init(key: "derived"),
            .init(key: "base", config: json(#"{"value":41}"#))
        ])
        let outcomes = await app.load(plan, registry: makeRegistry())
        #expect(outcomes.map(\.status) == [.pending, .active])
        #expect(outcomes.map(\.key) == ["derived", "base"])
        #expect(app[DerivedKey.self] == 42)
        #expect(app.snapshot().plugins.allSatisfy { $0.status == .active })
    }

    @Test
    func failedEntryDoesNotStopOthers() async {
        let app = Context.root()
        let plan = LoadPlan(entries: [
            .init(key: "broken"),
            .init(key: "base", name: "primary", config: json(#"{"value":1}"#))
        ])
        let outcomes = await app.load(plan, registry: makeRegistry())
        #expect(outcomes.count == 2)
        guard case .failed = outcomes[0].status else {
            Issue.record("expected failure, got \(outcomes[0].status)")
            return
        }

        #expect(outcomes[1].status == .active)
        #expect(outcomes[1].name == "primary")
        #expect(app[BaseKey.self] == 1)
    }

    @Test
    func configIsDecodedIntoPluginConfig() async {
        let app = Context.root()
        let plan = LoadPlan(entries: [.init(key: "base", config: json(#"{"value":7}"#))])
        _ = await app.load(plan, registry: makeRegistry())
        #expect(app[BaseKey.self] == 7)
    }
}
