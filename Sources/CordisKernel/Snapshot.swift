/// Opaque identity of a plugin application within one snapshot-able graph.
public struct PluginID: Hashable, Sendable {
    let raw: ObjectIdentifier

    init(_ raw: ObjectIdentifier) {
        self.raw = raw
    }
}

/// Provisional record shape: may change before it is declared stable.
public struct PluginInfo: Sendable {
    public let id: PluginID
    public let name: String
    public let status: Fork.Status
    public let parent: PluginID?
}

/// Provisional record shape: may change before it is declared stable.
public struct SlotInfo: Sendable {
    public let service: String
    public let realm: String
    public let provider: PluginID?
    public let generation: Int
}

/// Read-only, immutable copy of the graph. Provisional record shape.
/// Plugins are in registration order; slots are in provision order (ascending generation).
public struct RuntimeSnapshot: Sendable {
    public let plugins: [PluginInfo]
    public let slots: [SlotInfo]
}
