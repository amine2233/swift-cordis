import Cordis
import CordisTesting
import Testing

@CordisActor
final class Counter {
    var value = 0
}

enum TickerPlugin: Plugin {
    static func apply(_ ctx: Context, config: (ManualClock, Counter)) async throws {
        let counter = config.1
        try await ctx.every(.seconds(1), clock: config.0) { counter.value += 1 }
    }
}

enum TickKey: ServiceKey { typealias Value = Int }

@CordisActor
func waitForSleepers(_ clock: ManualClock, _ count: Int) async {
    await settle { clock.sleeperCount == count }
}

@CordisActor
@Suite
struct TimerTests {
    @Test
    func afterFiresOnce() async throws {
        let app = Context.root()
        let clock = ManualClock()
        let counter = Counter()
        try await app.after(.seconds(5), clock: clock) { counter.value += 1 }
        await waitForSleepers(clock, 1)
        clock.advance(by: .seconds(4))
        await Task.yield()
        #expect(counter.value == 0)
        clock.advance(by: .seconds(1))
        await settle { counter.value == 1 }
        clock.advance(by: .seconds(60))
        await Task.yield()
        #expect(counter.value == 1)
    }

    @Test
    func everyFiresRepeatedly() async throws {
        let app = Context.root()
        let clock = ManualClock()
        let counter = Counter()
        try await app.every(.seconds(1), clock: clock) { counter.value += 1 }
        for expected in 1 ... 3 {
            await waitForSleepers(clock, 1)
            clock.advance(by: .seconds(1))
            await settle { counter.value == expected }
            #expect(counter.value == expected)
        }
    }

    @Test
    func nothingFiresAfterDispose() async throws {
        let app = Context.root()
        let clock = ManualClock()
        let counter = Counter()
        let timer = try await app.every(.seconds(1), clock: clock) { counter.value += 1 }
        await waitForSleepers(clock, 1)
        await timer()
        #expect(timer.isDisposed)
        #expect(clock.sleeperCount == 0)
        clock.advance(by: .seconds(10))
        await Task.yield()
        #expect(counter.value == 0)
    }

    @Test
    func scopeDisposeCancelsTimer() async throws {
        let app = Context.root()
        let clock = ManualClock()
        let counter = Counter()
        try await app.every(.seconds(1), clock: clock) { counter.value += 1 }
        await waitForSleepers(clock, 1)
        await app.dispose()
        clock.advance(by: .seconds(10))
        await Task.yield()
        #expect(counter.value == 0)
        #expect(clock.sleeperCount == 0)
    }

    @Test
    func pluginRestartCancelsOldTimer() async {
        let app = Context.root()
        let clock = ManualClock()
        let counter = Counter()
        let handle = await app.plugin(TickerPlugin.self, (clock, counter))
        await waitForSleepers(clock, 1)
        await handle.update((clock, counter))
        await waitForSleepers(clock, 1)
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(1))
        await settle { counter.value >= 1 }
        await Task.yield()
        #expect(counter.value == 1)
        await handle.dispose()
        #expect(clock.sleeperCount == 0)
    }

    @Test
    func tickAwaitingGraphMutationDoesNotStallTeardown() async throws {
        let app = Context.root()
        let clock = ManualClock()
        let counter = Counter()
        try await app.every(.seconds(1), clock: clock) { [app] in
            try? await app.provide(TickKey.self, counter.value)
            counter.value += 1
        }
        await waitForSleepers(clock, 1)
        clock.advance(by: .seconds(1))
        await app.dispose()
        clock.advance(by: .seconds(10))
        await Task.yield()
        #expect(counter.value <= 1)
        #expect(clock.sleeperCount == 0)
    }
}
