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
        let zone: ZoneID?
        let handler: @CordisActor (Any) async -> Void
    }

    private var slots: [Slot: Entry] = [:]
    private var forks: [ObjectIdentifier: Fork] = [:]
    private(set) var listeners: [ObjectIdentifier: [Listener]] = [:]
    private var generation = 0
    private var listenerCounter = 0
    private var zoneParents: [ZoneID: ZoneID?] = [:]
    private var zoneChildren: [ZoneKey: ZoneID] = [:]

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
    }

    func unregister(_ fork: Fork) {
        forks[fork.id] = nil
    }

    // MARK: Events

    func on<E: Event>(_ type: E.Type, zone: ZoneID?, _ handler: @escaping @CordisActor (E) async -> Void) -> Int {
        listenerCounter += 1
        let listener = Listener(id: listenerCounter, zone: zone) { any in
            if let event = any as? E { await handler(event) }
        }
        listeners[ObjectIdentifier(type), default: []].append(listener)
        return listenerCounter
    }

    func off<E: Event>(_ type: E.Type, id: Int) {
        listeners[ObjectIdentifier(type)]?.removeAll { $0.id == id }
    }

    func zone(_ label: String, under parent: ZoneID?) -> ZoneID {
        let key = ZoneKey(parent: parent, label: label)
        if let existing = zoneChildren[key] { return existing }

        let id = ZoneID(rawValue: zoneParents.count)
        zoneParents[id] = .some(parent)
        zoneChildren[key] = id
        return id
    }

    private func isAncestorOrSelf(_ candidate: ZoneID, of zone: ZoneID?) -> Bool {
        var current = zone
        while let id = current {
            if id == candidate { return true }
            current = zoneParents[id] ?? nil
        }
        return false
    }

    func emit<E: Event>(_ event: E, from zone: ZoneID? = nil) async {
        // Snapshot: listeners added/removed during dispatch don't affect this round.
        for listener in listeners[ObjectIdentifier(E.self)] ?? [] {
            if let listenerZone = listener.zone, !isAncestorOrSelf(listenerZone, of: zone) { continue }

            await listener.handler(event)
        }
    }
}

extension Registry {
    func listenerCount<E: Event>(for type: E.Type) -> Int {
        listeners[ObjectIdentifier(type)]?.count ?? 0
    }
}

struct ZoneID: Hashable {
    let rawValue: Int
}

private struct ZoneKey: Hashable {
    let parent: ZoneID?
    let label: String
}
