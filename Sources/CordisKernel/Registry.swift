/// Shared state of one plugin graph: service slots, live forks, event listeners.
/// Internal — plugins only ever talk to `Context`.
@CordisActor
final class Registry {
    struct Entry {
        let value: Any
        let owner: ObjectIdentifier // providing Context
        let ownerName: String
        let fork: ObjectIdentifier? // providing Fork (nil = root)
        let generation: Int
    }

    struct Listener {
        let id: Int
        let handler: @CordisActor (Any) async -> Void
    }

    private var slots: [Slot: Entry] = [:]
    private var forks: [ObjectIdentifier: Fork] = [:]
    private var forkOrder: [ObjectIdentifier: Int] = [:]
    private var forkCounter = 0
    private(set) var listeners: [ObjectIdentifier: [Listener]] = [:]
    private var generation = 0
    private var listenerCounter = 0

    // MARK: Services

    func entry(_ slot: Slot) -> Entry? {
        slots[slot]
    }

    func provide(_ slot: Slot, value: Any, by ctx: Context) async throws {
        if let existing = slots[slot], existing.owner != ObjectIdentifier(ctx) {
            throw CordisError.serviceConflict(slot, existingOwner: existing.ownerName)
        }
        generation += 1
        slots[slot] = Entry(
            value: value,
            owner: ObjectIdentifier(ctx),
            ownerName: ctx.name,
            fork: ctx.fork.map(ObjectIdentifier.init),
            generation: generation
        )
        await changed(slot, isAvailable: true, fork: ctx.fork.map(ObjectIdentifier.init))
    }

    func withdraw(_ slot: Slot, owner: ObjectIdentifier, fork: ObjectIdentifier?) async {
        guard slots[slot]?.owner == owner else { return }

        slots[slot] = nil
        await changed(slot, isAvailable: false, fork: fork)
    }

    private var realmCounter = 0
    func anonymousRealm() -> String {
        realmCounter += 1
        return "anon-\(realmCounter)"
    }

    /// Propagates a slot change to every dependent fork. This is the whole "reactivity":
    /// dependents start, stop or restart, which may cascade into further slot changes.
    private func changed(_ slot: Slot, isAvailable: Bool, fork ownFork: ObjectIdentifier?) async {
        await emit(ServiceChanged(slot: slot, isAvailable: isAvailable))
        let dependents = forks.values.filter { $0.id != ownFork && $0.depends(on: slot) }
        for fork in dependents {
            await fork.refresh()
        }
    }

    // MARK: Forks

    func register(_ fork: Fork) {
        forks[fork.id] = fork
        forkCounter += 1
        forkOrder[fork.id] = forkCounter
    }

    func unregister(_ fork: Fork) {
        forks[fork.id] = nil
        forkOrder[fork.id] = nil
    }

    func snapshot() -> RuntimeSnapshot {
        let plugins = forks.values
            .sorted { (forkOrder[$0.id] ?? 0) < (forkOrder[$1.id] ?? 0) }
            .map { fork in
                PluginInfo(
                    id: PluginID(fork.id),
                    name: fork.name,
                    status: fork.status,
                    parent: fork.parent.fork.map { PluginID($0.id) }
                )
            }
        let slotInfos = slots
            .sorted { $0.value.generation < $1.value.generation }
            .map { slot, entry in
                SlotInfo(
                    service: slot.service.description,
                    realm: slot.realm,
                    provider: entry.fork.map(PluginID.init),
                    generation: entry.generation
                )
            }
        return RuntimeSnapshot(plugins: plugins, slots: slotInfos)
    }

    // MARK: Events

    func on<E: Event>(_ type: E.Type, _ handler: @escaping @CordisActor (E) async -> Void) -> Int {
        listenerCounter += 1
        let listener = Listener(id: listenerCounter) { any in
            if let event = any as? E { await handler(event) }
        }
        listeners[ObjectIdentifier(type), default: []].append(listener)
        return listenerCounter
    }

    func off<E: Event>(_ type: E.Type, id: Int) {
        listeners[ObjectIdentifier(type)]?.removeAll { $0.id == id }
    }

    func emit<E: Event>(_ event: E) async {
        // Snapshot: listeners added/removed during dispatch don't affect this round.
        for listener in listeners[ObjectIdentifier(E.self)] ?? [] {
            await listener.handler(event)
        }
    }
}

extension Registry {
    func listenerCount<E: Event>(for type: E.Type) -> Int {
        listeners[ObjectIdentifier(type)]?.count ?? 0
    }
}
