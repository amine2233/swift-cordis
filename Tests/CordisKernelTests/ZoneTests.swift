import Testing
@testable import CordisKernel

struct Order: Event {}

enum ZoneListener: Plugin {
    static func apply(_ ctx: Context, config: (Probe, String)) async throws {
        let (probe, name) = config
        ctx.on(Order.self) { _ in probe.log.append(name) }
    }
}

@CordisActor
@Suite
struct ZoneTests {
    let root = Context.root()
    let probe = Probe()

    func listen(_ ctx: Context, _ name: String) {
        ctx.on(Order.self) { [probe] _ in probe.log.append(name) }
    }

    @Test
    func tenantsAreIsolated() async {
        let a = root.zone("a")
        let b = root.zone("b")
        listen(a, "a")
        listen(b, "b")
        await a.emit(Order())
        #expect(probe.log == ["a"])
    }

    @Test
    func ancestorReceivesDescendantEvents() async {
        let a = root.zone("a")
        let child = a.zone("x")
        listen(a, "a")
        listen(child, "x")
        await child.emit(Order())
        await a.emit(Order())
        #expect(probe.log == ["a", "x", "a"])
    }

    @Test
    func sameLabelUnderSameParentIsSameZone() async {
        listen(root.zone("a"), "first")
        await root.zone("a").emit(Order())
        #expect(probe.log == ["first"])
    }

    @Test
    func sameLabelUnderDifferentParentsDiffers() async {
        listen(root.zone("a").zone("x"), "ax")
        await root.zone("b").zone("x").emit(Order())
        #expect(probe.log.isEmpty)
    }

    @Test
    func globalListenerSeesEverything() async {
        listen(root, "global")
        await root.zone("a").emit(Order())
        await root.emit(Order())
        #expect(probe.log == ["global", "global"])
    }

    @Test
    func globalEmitReachesOnlyGlobalListeners() async {
        listen(root, "global")
        listen(root.zone("a"), "a")
        await root.emit(Order())
        #expect(probe.log == ["global"])
    }

    @Test
    func zoneIsInheritedThroughIsolate() async {
        let a = root.zone("a")
        let isolated = a.isolate(ValueKey.self, label: "t")
        listen(isolated, "iso")
        await a.emit(Order())
        await root.zone("b").emit(Order())
        #expect(probe.log == ["iso"])
    }

    @Test
    func zoneIsInheritedByPlugins() async {
        let a = root.zone("a")
        await a.plugin(ZoneListener.self, (probe, "plugin"))
        await a.emit(Order())
        await root.zone("b").emit(Order())
        #expect(probe.log == ["plugin"])
    }

    @Test
    func disposeRemovesZonedListener() async {
        let a = root.zone("a")
        listen(a, "a")
        await a.scope.dispose()
        await a.emit(Order())
        #expect(probe.log.isEmpty)
        #expect(root.registry.listenerCount(for: Order.self) == 0)
    }

    @Test
    func emitUsesSnapshotWithZones() async {
        let a = root.zone("a")
        a.on(Order.self) { [probe, a] _ in
            probe.log.append("first")
            a.on(Order.self) { _ in probe.log.append("late") }
        }
        await a.emit(Order())
        #expect(probe.log == ["first"])
    }
}
