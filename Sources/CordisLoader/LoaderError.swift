@_exported import Cordis

/// Every problem the loader can report while validating a plan.
public enum LoaderError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No plugin is registered under the entry's key.
    case unknownKey(String, entry: Int)
    /// Two entries share the same name.
    case duplicateName(String, entry: Int)
    /// The entry's JSON config failed to decode into the plugin's config type.
    case invalidConfig(String, entry: Int, reason: String)

    /// Human-readable message for the error.
    public var description: String {
        switch self {
        case let .unknownKey(key, entry): "Entry \(entry): no plugin registered under key '\(key)'"
        case let .duplicateName(name, entry): "Entry \(entry): duplicate entry name '\(name)'"
        case let .invalidConfig(key, entry, reason): "Entry \(entry) ('\(key)'): invalid config: \(reason)"
        }
    }
}
