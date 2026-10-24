/// Typed service key, same idea as SwiftUI's `EnvironmentKey`.
///
///     enum DatabaseKey: ServiceKey { typealias Value = any Database }
///
/// `Value` is usually a protocol so implementations can be hot-swapped.
public protocol ServiceKey {
    associatedtype Value
}

/// Type-erased identity of a service key.
public struct ServiceID: Hashable, Sendable, CustomStringConvertible {
    let raw: ObjectIdentifier
    public let description: String

    public init(_ key: Any.Type) {
        self.raw = ObjectIdentifier(key)
        self.description = String(describing: key)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.raw == rhs.raw
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(raw)
    }
}

extension ServiceKey {
    public static var id: ServiceID {
        ServiceID(Self.self)
    }
}

/// Declares what a plugin needs.
/// - `required`: the plugin stays *pending* until all of them exist, and stops if one disappears.
/// - `optional`: the plugin starts without them, but restarts when they appear / change / vanish.
public struct Inject: Sendable {
    public var required: [ServiceID]
    public var optional: [ServiceID]

    public init(required: [any ServiceKey.Type] = [], optional: [any ServiceKey.Type] = []) {
        self.required = required.map { ServiceID($0) }
        self.optional = optional.map { ServiceID($0) }
    }

    public static let none = Inject()

    var all: [ServiceID] {
        required + optional
    }
}

/// Address of a service instance: (which service, in which isolation realm).
/// Realms are the "space" half of spatiotemporal composability.
public struct Slot: Hashable, Sendable, CustomStringConvertible {
    public let service: ServiceID
    public let realm: String
    public var description: String {
        realm == Slot.sharedRealm ? "\(service)" : "\(service)@\(realm)"
    }

    public static let sharedRealm = "shared"
}

public enum CordisError: Error, CustomStringConvertible {
    case missingService(ServiceID)
    case serviceConflict(Slot, existingOwner: String)
    case disposed

    public var description: String {
        switch self {
        case let .missingService(id): "Service \(id) is not available in this context"
        case let .serviceConflict(slot, owner): "Service \(slot) is already provided by \(owner)"
        case .disposed: "Context has been disposed"
        }
    }
}

// MARK: - Events

/// Any value type can be an event; dispatch is keyed by the concrete type.
public protocol Event {}

/// Emitted whenever a slot gets a new instance or loses it.
public struct ServiceChanged: Event {
    public let slot: Slot
    public let isAvailable: Bool
}

/// Emitted when a plugin's `apply` throws. The plugin's scope is rolled back.
public struct PluginFailed: Event {
    public let plugin: String
    public let error: any Error
}

/// Emitted when a teardown throws. Remaining teardowns of the same scope still run.
/// `plugin` is the name of the owning context (`root` for the graph root).
public struct TeardownFailed: Event {
    public let plugin: String
    public let error: any Error
}

/// Emitted on every plugin status transition (handy for a devtools/console plugin).
public struct PluginStatusChanged: Event {
    public let plugin: String
    public let status: Fork.Status
}
