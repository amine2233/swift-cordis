import Foundation

final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private enum Registration {
        case registered
        case cancelled
        case elapsed
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]

    var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var minimumResolution: Duration {
        .zero
    }

    var sleeperCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    private func register(
        _ id: UUID,
        deadline: Instant,
        continuation: CheckedContinuation<Void, any Error>
    ) -> Registration {
        lock.lock()
        defer { lock.unlock() }
        if Task.isCancelled { return .cancelled }
        if deadline <= current { return .elapsed }

        sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
        return .registered
    }

    private func remove(_ id: UUID) -> Sleeper? {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.removeValue(forKey: id)
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                any Error
            >) in
                switch register(id, deadline: deadline, continuation: continuation) {
                case .registered: break
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .elapsed: continuation.resume()
                }
            }
        } onCancel: {
            remove(id)?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        let ready = sleepers.filter { $0.value.deadline <= current }
        for key in ready.keys {
            sleepers[key] = nil
        }
        lock.unlock()
        for sleeper in ready.values.sorted(by: { $0.deadline < $1.deadline }) {
            sleeper.continuation.resume()
        }
    }
}
