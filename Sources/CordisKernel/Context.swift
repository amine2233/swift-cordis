/// The only API a plugin sees. A context is a view on the plugin graph with:
/// - a **scope** (time): everything registered through it dies with it;
/// - a set of **realms** (space): which instance of each service it resolves to.
///
/// Expose services as Cordis-style mixins with a plain extension:
///
///     extension Context {
///         var database: (any Database)? { self[DatabaseKey.self] }
///     }
@CordisActor
public final class Context {
    let registry: Registry
    public let scope: Scope
    public let parent: Context?
    let fork: Fork?
    private var realms: [ServiceID: String]
    let zoneID: ZoneID?

    public var name: String {
        fork?.name ?? "root"
    }

    init(
        registry: Registry,
        parent: Context?,
        fork: Fork?,
        scope: Scope,
        realms: [ServiceID: String]? = nil,
        zoneID: ZoneID? = nil
    ) {
        self.registry = registry
        self.parent = parent
        self.fork = fork
        self.scope = scope
        self.realms = realms ?? parent?.realms ?? [:]
        self.zoneID = zoneID ?? parent?.zoneID
    }

    /// Creates the root of a new plugin graph (your "App").
    public static func root() -> Context {
        let registry = Registry()
        let scope = Scope { error in
            await registry.emit(TeardownFailed(plugin: "root", error: error))
        }
        return Context(registry: registry, parent: nil, fork: nil, scope: scope)
    }

    /// Tears down the whole graph, children first.
    public func dispose() async {
        await scope.dispose()
    }

    func slot(for service: ServiceID) -> Slot {
        Slot(service: service, realm: realms[service] ?? Slot.sharedRealm)
    }

    // MARK: Services

    public subscript<K: ServiceKey>(_ key: K.Type) -> K.Value? {
        registry.entry(slot(for: K.id))?.value as? K.Value
    }

    public func require<K: ServiceKey>(_ key: K.Type) throws -> K.Value {
        guard let value = self[key] else { throw CordisError.missingService(K.id) }

        return value
    }

    /// Registers a service instance in this context's realm.
    /// Withdrawn automatically when this context's scope is disposed,
    /// which in turn stops/restarts every plugin that injected it.
    public func provide<K: ServiceKey>(_ key: K.Type, _ value: K.Value) async throws {
        guard !scope.isDisposed else { throw CordisError.disposed }

        let slot = slot(for: K.id)
        try await registry.provide(slot, value: value, by: self)
        let owner = ObjectIdentifier(self)
        let forkID = fork.map(ObjectIdentifier.init)
        scope.collect { [registry] in
            await registry.withdraw(slot, owner: owner, fork: forkID)
        }
    }

    // MARK: Space — isolation

    /// Returns a child context where `key` resolves to a separate realm.
    /// Same `label` ⇒ shared realm (e.g. one DB per tenant, shared by that tenant's plugins).
    /// No label ⇒ a private, anonymous realm.
    public func isolate<K: ServiceKey>(_ key: K.Type, label: String? = nil) -> Context {
        var realms = realms
        realms[K.id] = label ?? registry.anonymousRealm()
        return Context(
            registry: registry,
            parent: self,
            fork: fork,
            scope: scope,
            realms: realms,
            zoneID: zoneID
        )
    }

    // MARK: Event routing — zones

    /// Returns a child context in the zone `label` under this context's zone.
    /// Listeners registered through it only hear events emitted from the same zone or a descendant;
    /// listeners with no zone hear everything. Independent of scope and realms; not an authorization
    /// boundary.
    public func zone(_ label: String) -> Context {
        Context(
            registry: registry,
            parent: self,
            fork: fork,
            scope: scope,
            realms: realms,
            zoneID: registry.zone(label, under: zoneID)
        )
    }

    // MARK: Composition

    /// Loads a sub-plugin. Its lifetime is bound to this context:
    /// unloading the parent unloads the whole subtree.
    @discardableResult
    public func plugin<P: Plugin>(_ plugin: P.Type, _ config: P.Config) async -> PluginHandle<P> {
        let fork = Fork(name: P.name, inject: P.inject, parent: self) { ctx in
            try await P.apply(ctx, config: config)
        }
        registry.register(fork)
        scope.collect { await fork.dispose() }
        if !scope.isDisposed { await fork.refresh() }
        return PluginHandle(fork: fork)
    }

    @discardableResult
    public func plugin<P: Plugin>(_ plugin: P.Type) async -> PluginHandle<P> where P.Config == Void {
        await self.plugin(plugin, ())
    }

    // MARK: Effects & events

    /// Registers a teardown for this context.
    public func onDispose(_ teardown: @escaping Disposer) {
        scope.collect(teardown)
    }

    /// Cordis' `ctx.effect`: run setup now, run the returned teardown on dispose.
    ///
    ///     try await ctx.effect {
    ///         let timer = startTimer()
    ///         return { timer.invalidate() }
    ///     }
    @discardableResult
    public func effect(_ setup: @CordisActor () async throws -> Disposer) async throws -> Disposable {
        let teardown = try await setup()
        return scope.collect(teardown)
    }

    /// Subscribes to an event type. Automatically unsubscribed with this context.
    @discardableResult
    public func on<E: Event>(
        _ type: E.Type,
        _ handler: @escaping @CordisActor (E) async -> Void
    ) -> Disposable {
        let id = registry.on(type, zone: zoneID, handler)
        return scope.collect { [registry] in registry.off(type, id: id) }
    }

    public func emit<E: Event>(_ event: E) async {
        await registry.emit(event, from: zoneID)
    }
}
