import Cordis
import Testing

enum GreetingKey: ServiceKey { typealias Value = String }

enum GreetingPlugin: ServicePlugin {
    typealias Key = GreetingKey
    typealias Config = String
    static func make(_ ctx: Context, config: String) async throws -> String {
        "hello \(config)"
    }
}

enum BrokenGreetingPlugin: ServicePlugin {
    struct Boom: Error {}
    typealias Key = GreetingKey
    static func make(_ ctx: Context, config: Void) async throws -> String {
        throw Boom()
    }
}

@CordisActor
@Suite
struct ServicePluginTests {
    @Test
    func providesMadeValue() async {
        let app = Context.root()
        let handle = await app.plugin(GreetingPlugin.self, "world")
        #expect(handle.status == .active)
        #expect(app[GreetingKey.self] == "hello world")
    }

    @Test
    func updateReprovidesNewValue() async {
        let app = Context.root()
        let handle = await app.plugin(GreetingPlugin.self, "a")
        await handle.update("b")
        #expect(app[GreetingKey.self] == "hello b")
    }

    @Test
    func disposeWithdrawsService() async {
        let app = Context.root()
        let handle = await app.plugin(GreetingPlugin.self, "a")
        await handle.dispose()
        #expect(app[GreetingKey.self] == nil)
    }

    @Test
    func failingMakeLeavesNothingProvided() async {
        let app = Context.root()
        let handle = await app.plugin(BrokenGreetingPlugin.self)
        guard case .failed = handle.status else { Issue.record("expected failure"); return }

        #expect(app[GreetingKey.self] == nil)
    }

    @Test
    func cordisReExportsKernel() {
        let app = Context.root()
        #expect(app.name == "root")
    }
}
