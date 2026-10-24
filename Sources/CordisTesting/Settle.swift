import CordisKernel

/// Yields up to 10 000 times until `condition` holds; returns whether it did.
@discardableResult
@CordisActor
public func settle(until condition: () -> Bool) async -> Bool {
    for _ in 0 ..< 10_000 where !condition() {
        await Task.yield()
    }
    return condition()
}
