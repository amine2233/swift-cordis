import Foundation

/// Maps string resolve keys to plugin types; the only place strings name plugins.
public struct PluginRegistry: Sendable {
    typealias Loader = @CordisActor (Context) async -> Fork.Status

    private var makers: [String: @Sendable (Data?) throws -> Loader] = [:]

    /// Creates an empty registry.
    public init() {}

    /// Registers `plugin` under `key`; the config is produced by `decode` from the entry's JSON.
    public mutating func register<P: Plugin>(
        _ plugin: P.Type,
        key: String,
        decode: @escaping @Sendable (Data?) throws -> P.Config
    ) {
        makers[key] = { data in
            let config = try decode(data)
            return { ctx in await ctx.plugin(plugin, config).status }
        }
    }

    /// Registers `plugin` under `key`, decoding its `Config` from JSON (a config is then required).
    public mutating func register<P: Plugin>(_ plugin: P.Type, key: String) where P.Config: Decodable {
        register(plugin, key: key) { data in
            guard let data else { throw LoaderConfigMissing() }

            return try JSONDecoder().decode(P.Config.self, from: data)
        }
    }

    /// Registers a plugin without configuration under `key`.
    public mutating func register<P: Plugin>(_ plugin: P.Type, key: String) where P.Config == Void {
        register(plugin, key: key) { _ in () }
    }

    func isRegistered(_ key: String) -> Bool {
        makers[key] != nil
    }

    func loader(for key: String, config: Data?) throws -> Loader? {
        try makers[key]?(config)
    }
}

struct LoaderConfigMissing: Error, CustomStringConvertible {
    var description: String {
        "config is required"
    }
}
