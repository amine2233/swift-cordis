import CordisKernel

extension Context {
    /// Runs `body` once after `delay`; cancelled when this context is disposed.
    @discardableResult
    public func after(
        _ delay: Duration,
        clock: some Clock<Duration> = ContinuousClock(),
        _ body: @escaping @CordisActor () async -> Void
    ) async throws -> Disposable {
        try await ownTask {
            do {
                try await clock.sleep(until: clock.now.advanced(by: delay), tolerance: nil)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            await body()
        }
    }

    /// Runs `body` every `interval`; cancelled when this context is disposed.
    @discardableResult
    public func every(
        _ interval: Duration,
        clock: some Clock<Duration> = ContinuousClock(),
        _ body: @escaping @CordisActor () async -> Void
    ) async throws -> Disposable {
        try await ownTask {
            var deadline = clock.now.advanced(by: interval)
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: deadline, tolerance: nil)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                await body()
                deadline = deadline.advanced(by: interval)
            }
        }
    }

    private func ownTask(_ run: @escaping @CordisActor () async -> Void) async throws -> Disposable {
        try await effect {
            let task = Task { @CordisActor in await run() }
            return {
                task.cancel()
                await task.value
            }
        }
    }
}
