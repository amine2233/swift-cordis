import CordisKernel

/// Lifecycle and failure events captured during a `withTestApp` run, in emission order.
@CordisActor
public final class RecordedEvents {
    /// Every recorded event in emission order.
    public private(set) var all: [any Event] = []

    init() {}

    /// The recorded events of type `E`, in emission order.
    public func ofType<E: Event>(_: E.Type) -> [E] {
        all.compactMap { $0 as? E }
    }

    /// The `PluginFailed` and `TeardownFailed` entries, in emission order.
    public var failures: [any Event] {
        all.filter { $0 is PluginFailed || $0 is TeardownFailed }
    }

    func record(_ event: any Event) {
        all.append(event)
    }
}

/// Runs `body` against a fresh root context, always disposes it, and returns the recorded events.
@discardableResult
@CordisActor
public func withTestApp(
    _ body: @CordisActor (Context, RecordedEvents) async throws -> Void
) async rethrows -> RecordedEvents {
    let ctx = Context.root()
    let events = RecordedEvents()
    ctx.on(PluginFailed.self) { events.record($0) }
    ctx.on(PluginStatusChanged.self) { events.record($0) }
    ctx.on(ServiceChanged.self) { events.record($0) }
    ctx.on(TeardownFailed.self) { events.record($0) }
    do {
        try await body(ctx, events)
    } catch {
        await ctx.dispose()
        throw error
    }
    await ctx.dispose()
    return events
}
