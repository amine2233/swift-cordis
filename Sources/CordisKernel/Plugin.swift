/// Everything is a plugin: features, services, adapters, even the app shell.
///
///     enum Greeter: Plugin {
///         static let inject = Inject(required: [LoggerKey.self])
///         static func apply(_ ctx: Context, config: String) async throws {
///             try ctx.require(LoggerKey.self).info("Hello \(config)")
///         }
///     }
///
/// `apply` must only *register* side effects through `ctx` (provide, on, effect, plugin…).
/// Anything registered that way is automatically undone when the plugin is unloaded
/// or restarted — you never write a matching "unregister" by hand.
@CordisActor
public protocol Plugin {
    associatedtype Config = Void
    static var name: String { get }
    static var inject: Inject { get }
    @CordisActor
    static func apply(_ ctx: Context, config: Config) async throws
    /// Checks the shape of a config before `update` tears anything down; throw to reject it.
    static func validate(config: Config) throws
}

extension Plugin {
    public static var name: String {
        String(describing: Self.self)
    }

    public static var inject: Inject {
        .none
    }

    /// Default validation accepts every config.
    public static func validate(config: Config) throws {}
}

/// Result of `PluginHandle.update`: whether the new config was accepted for application.
public enum UpdateOutcome: Sendable {
    /// The config passed validation and was applied; read `status` for the apply result.
    case applied
    /// Validation threw; the running instance was left untouched.
    case rejected(any Error)
    /// The plugin is active and the config equals the last applied one, so nothing was restarted.
    case unchanged
}

/// One application of a plugin in a given context (Cordis calls this a "fork").
/// It owns a reactive lifecycle: pending → loading → active, and back,
/// driven by the availability of its injected services.
@CordisActor
public final class Fork {
    public enum Status: Equatable, Sendable {
        case pending // waiting for required services
        case loading // apply() in flight
        case active
        case failed(String)
        case disposed
    }

    public let name: String
    public private(set) var status: Status = .pending

    let inject: Inject
    let parent: Context
    private let registry: Registry
    private var body: @CordisActor (Context) async throws -> Void
    private var config: Any?
    private var appliedConfig: Any?

    private struct Runtime {
        let context: Context
        let snapshot: [Slot: OccurrenceID?]
    }

    private var runtime: Runtime?
    private var isReconciling = false
    private var needsReconcile = false
    private var forceRestart = false

    init(
        name: String,
        inject: Inject,
        parent: Context,
        config: Any? = nil,
        body: @escaping @CordisActor (Context) async throws -> Void
    ) {
        self.config = config
        self.name = name
        self.inject = inject
        self.parent = parent
        self.registry = parent.registry
        self.body = body
    }

    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    // MARK: Reactive core

    /// Does this fork react to changes on `slot`?
    func depends(on slot: Slot) -> Bool {
        inject.all.contains { parent.slot(for: $0) == slot }
    }

    /// Current occurrences of every injected slot, or `nil` if a required one is missing.
    /// Slots provided by this very fork are ignored to avoid self-restart loops.
    private func resolve() -> [Slot: OccurrenceID?]? {
        var snapshot: [Slot: OccurrenceID?] = [:]
        for id in inject.required {
            let slot = parent.slot(for: id)
            guard let entry = registry.entry(slot) else { return nil }

            if entry.fork == self.id { continue }
            snapshot[slot] = entry.occurrence
        }
        for id in inject.optional {
            let slot = parent.slot(for: id)
            let entry = registry.entry(slot)
            if entry?.fork == self.id { continue }
            snapshot[slot] = .some(entry?.occurrence)
        }
        return snapshot
    }

    /// Serialized, re-entrancy-safe reconciliation (think React reconciler, but for plugins).
    func refresh() async {
        if isReconciling { needsReconcile = true; return }
        isReconciling = true
        repeat {
            needsReconcile = false
            await reconcile()
        } while needsReconcile
        isReconciling = false
    }

    private func reconcile() async {
        guard status != .disposed else { return }

        let wanted = resolve()
        switch (runtime, wanted) {
        case (nil, nil):
            await setStatus(.pending)
        case (nil, let snapshot?):
            await start(snapshot)
        case (_?, nil):
            await stop()
            await setStatus(.pending)
        case let (current?, snapshot?):
            if forceRestart || current.snapshot != snapshot {
                await stop()
                await start(snapshot)
            }
        }
        forceRestart = false
    }

    private func start(_ snapshot: [Slot: OccurrenceID?]) async {
        let scope = Scope { [registry, name] error in
            await registry.emit(TeardownFailed(plugin: name, error: error))
        }
        let ctx = Context(registry: registry, parent: parent, fork: self, scope: scope)
        runtime = Runtime(context: ctx, snapshot: snapshot)
        await setStatus(.loading)
        do {
            try await body(ctx)
            if status == .loading {
                appliedConfig = config
                await setStatus(.active)
            }
        } catch {
            await stop()
            await setStatus(.failed(String(describing: error)))
            await parent.emit(PluginFailed(plugin: name, error: error))
        }
    }

    private func stop() async {
        guard let current = runtime else { return }

        runtime = nil
        await current.context.scope.dispose()
    }

    private func setStatus(_ new: Status) async {
        guard new != status else { return }

        status = new
        await parent.emit(PluginStatusChanged(plugin: name, status: new))
    }

    // MARK: Public controls

    /// Replaces the plugin body (new config) and restarts if running, unless the config equals the last
    /// applied one.
    func reconfigure(
        config: Any,
        _ body: @escaping @CordisActor (Context) async throws -> Void
    ) async -> Bool {
        if status == .active, let appliedConfig, isEqual(appliedConfig, config) { return false }

        self.config = config
        self.body = body
        forceRestart = true
        await refresh()
        return true
    }

    public func dispose() async {
        guard status != .disposed else { return }

        await stop()
        await setStatus(.disposed)
        registry.unregister(self)
    }
}

/// Typed handle returned by `ctx.plugin(...)`.
@CordisActor
public struct PluginHandle<P: Plugin> {
    public let fork: Fork

    public var status: Fork.Status {
        fork.status
    }

    /// Hot-reconfigure: validates the config, then tears the plugin down and re-applies it.
    /// A no-op (`.unchanged`) when the plugin is active and an `Equatable` config equals the last applied
    /// one.
    @discardableResult
    public func update(_ config: P.Config) async -> UpdateOutcome {
        do {
            try P.validate(config: config)
        } catch {
            return .rejected(error)
        }
        let restarted = await fork
            .reconfigure(config: config) { ctx in try await P.apply(ctx, config: config) }
        return restarted ? .applied : .unchanged
    }

    /// Hot-unload: every side effect of this plugin (and its sub-plugins) is rolled back.
    public func dispose() async {
        await fork.dispose()
    }
}

private func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    guard let lhs = lhs as? any Equatable else { return false }

    return isEqual(opened: lhs, rhs)
}

private func isEqual<T: Equatable>(opened lhs: T, _ rhs: Any) -> Bool {
    guard let rhs = rhs as? T else { return false }

    return lhs == rhs
}
