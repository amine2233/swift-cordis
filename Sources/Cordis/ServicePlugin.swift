import CordisKernel

/// Sugar for the most common case: a plugin whose only job is to provide one service.
@CordisActor
public protocol ServicePlugin: Plugin {
    associatedtype Key: ServiceKey
    @CordisActor
    static func make(_ ctx: Context, config: Config) async throws -> Key.Value
}

extension ServicePlugin {
    @CordisActor
    public static func apply(_ ctx: Context, config: Config) async throws {
        let service = try await make(ctx, config: config)
        try await ctx.provide(Key.self, service)
    }
}
