import Foundation

/// An ordered, declarative list of plugins to load, resolved through a `PluginRegistry`.
public struct LoadPlan: Sendable {
    /// One plugin to load: a resolve key, an optional unique name and optional JSON config.
    public struct Entry: Sendable {
        /// Resolve key of the plugin in the registry.
        public let key: String
        /// Optional label, unique within the plan.
        public let name: String?
        /// Optional JSON config decoded into the plugin's own `Config`.
        public let config: Data?

        /// Creates an entry for the plugin registered under `key`.
        public init(key: String, name: String? = nil, config: Data? = nil) {
            self.key = key
            self.name = name
            self.config = config
        }
    }

    /// Entries in load order.
    public let entries: [Entry]

    /// Creates a plan; call `validate(against:)` or `Context.load` to check it.
    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Returns every error in the plan (unknown key, duplicate name, undecodable config); empty when valid.
    public func validate(against registry: PluginRegistry) -> [LoaderError] {
        var errors: [LoaderError] = []
        var seenNames: Set<String> = []
        for (index, entry) in entries.enumerated() {
            if let name = entry.name, !seenNames.insert(name).inserted {
                errors.append(.duplicateName(name, entry: index))
            }
            guard registry.isRegistered(entry.key) else {
                errors.append(.unknownKey(entry.key, entry: index))
                continue
            }

            do {
                _ = try registry.loader(for: entry.key, config: entry.config)
            } catch {
                errors.append(.invalidConfig(entry.key, entry: index, reason: String(describing: error)))
            }
        }
        return errors
    }
}
