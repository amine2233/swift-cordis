import CordisKernel
import Foundation

/// A deterministic clock that only moves when `advance(by:)` is called.
public final class ManualClock: Clock, @unchecked Sendable {
    /// A point in time measured as an offset from the clock's start.
    public struct Instant: InstantProtocol {
        public var offset: Duration

        /// Creates an instant at `offset` from the clock's start.
        public init(offset: Duration) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
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

    /// Creates a clock at its start instant with no sleepers.
    public init() {}

    public var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public var minimumResolution: Duration {
        .zero
    }

    /// Number of tasks currently suspended in `sleep`.
    public var sleeperCount: Int {
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

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
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

    /// Moves the clock forward and resumes every sleeper whose deadline has passed.
    public func advance(by duration: Duration) {
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
