import CordisKernel
import CordisTesting
import Testing

@CordisActor
@Suite
struct ClockAndSettleTests {
    @Test
    func advanceResumesDueSleepersOnly() async {
        let clock = ManualClock()
        var woke = 0
        let task = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(5)), tolerance: nil)
            await MainActor.run { woke += 1 }
        }
        await settle { clock.sleeperCount == 1 }
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(4))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(1))
        #expect(clock.sleeperCount == 0)
        _ = await task.result
    }

    @Test
    func concurrentAdvanceIsSafe() async {
        let clock = ManualClock()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { clock.advance(by: .milliseconds(1)) }
            }
        }
        #expect(clock.now.offset == .milliseconds(100))
    }

    @Test
    func settleReturnsFalseWhenConditionNeverHolds() async {
        #expect(await settle { false } == false)
    }

    @Test
    func settleReturnsTrueWhenConditionHolds() async {
        var ticks = 0
        let held = await settle {
            ticks += 1
            return ticks > 3
        }
        #expect(held)
    }
}
