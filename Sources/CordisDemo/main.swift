import Cordis

// MARK: - Service contracts (the "public API" of the graph)

@CordisActor
protocol Logger: AnyObject { func info(_ message: String) }
@CordisActor
protocol Database: AnyObject {
    var label: String { get }
    func save(_ key: String, _ value: String)
    func load(_ key: String) -> String?
}

@CordisActor
final class UserRepository {
    private let db: any Database
    init(db: any Database) {
        self.db = db
    }

    func create(_ name: String) {
        db.save("user:\(name)", name)
    }

    func find(_ name: String) -> String? {
        db.load("user:\(name)")
    }

    var backend: String {
        db.label
    }
}

enum LoggerKey: ServiceKey { typealias Value = any Logger }
enum DatabaseKey: ServiceKey { typealias Value = any Database }
enum UserRepositoryKey: ServiceKey { typealias Value = UserRepository }

/// Cordis-style mixins: `ctx.logger`, `ctx.database`…
extension Context {
    var logger: (any Logger)? {
        self[LoggerKey.self]
    }

    var database: (any Database)? {
        self[DatabaseKey.self]
    }

    var users: UserRepository? {
        self[UserRepositoryKey.self]
    }
}

// MARK: - Plugins (implementations)

@CordisActor
final class ConsoleLogger: Logger {
    let prefix: String
    init(prefix: String) {
        self.prefix = prefix
    }

    func info(_ message: String) {
        print("\(prefix) \(message)")
    }
}

enum ConsoleLoggerPlugin: ServicePlugin {
    typealias Key = LoggerKey
    typealias Config = String
    static func make(_ ctx: Context, config: String) async throws -> any Logger {
        ConsoleLogger(prefix: config)
    }
}

@CordisActor
final class InMemoryDatabase: Database {
    let label: String
    private var storage: [String: String] = [:]
    init(label: String) {
        self.label = label
    }

    func save(_ key: String, _ value: String) {
        storage[key] = value
    }

    func load(_ key: String) -> String? {
        storage[key]
    }
}

/// A DB driver. Swapping it at runtime restarts everything that depends on it.
enum InMemoryDatabasePlugin: ServicePlugin {
    typealias Key = DatabaseKey
    typealias Config = String
    static let inject = Inject(optional: [LoggerKey.self])

    static func make(_ ctx: Context, config: String) async throws -> any Database {
        ctx.logger?.info("🔌 DB '\(config)' connected")
        ctx.onDispose { ctx.logger?.info("🔌 DB '\(config)' closed") }
        return InMemoryDatabase(label: config)
    }
}

/// Domain service built on top of another service.
enum UserRepositoryPlugin: Plugin {
    static let inject = Inject(required: [DatabaseKey.self], optional: [LoggerKey.self])

    static func apply(_ ctx: Context, config: Void) async throws {
        let db = try ctx.require(DatabaseKey.self)
        try await ctx.provide(UserRepositoryKey.self, UserRepository(db: db))
        ctx.logger?.info("👤 UserRepository ready on '\(db.label)'")
    }
}

struct UserSignedUp: Event { let name: String }

/// A feature: reacts to events, uses services, cleans up by itself.
enum WelcomeFeature: Plugin {
    static let inject = Inject(required: [UserRepositoryKey.self], optional: [LoggerKey.self])

    static func apply(_ ctx: Context, config: Void) async throws {
        let users = try ctx.require(UserRepositoryKey.self)
        ctx.on(UserSignedUp.self) { event in
            users.create(event.name)
            ctx.logger?.info("🎉 Welcome \(event.name) (stored in '\(users.backend)')")
        }
    }
}

// MARK: - Composition root

@CordisActor
func runDemo() async throws {
    let app = Context.root()

    app.on(PluginStatusChanged.self) { e in print("   · \(e.plugin) → \(e.status)") }

    print("\n1) Load features BEFORE their dependencies — they wait (pending)")
    await app.plugin(WelcomeFeature.self)
    await app.plugin(UserRepositoryPlugin.self)
    await app.plugin(ConsoleLoggerPlugin.self, "[app]")

    print("\n2) Plug a database — the whole chain comes alive")
    let db = await app.plugin(InMemoryDatabasePlugin.self, "sqlite")
    await app.emit(UserSignedUp(name: "Amine"))

    print("\n3) Hot-swap the DB driver — dependents restart automatically")
    await db.update("postgres")
    await app.emit(UserSignedUp(name: "Michel"))

    print("\n4) Unplug the DB — dependents go back to pending, listeners removed")
    await db.dispose()
    await app.emit(UserSignedUp(name: "Ghost")) // nobody listening anymore

    print("\n5) Space: two isolated tenants, each with its own DB, same plugins")
    for tenant in ["acme", "globex"] {
        let scoped = app
            .isolate(DatabaseKey.self, label: tenant)
            .isolate(UserRepositoryKey.self, label: tenant)
        await scoped.plugin(InMemoryDatabasePlugin.self, "db-\(tenant)")
        await scoped.plugin(UserRepositoryPlugin.self)
    }
    let acme = app.isolate(UserRepositoryKey.self, label: "acme")
    acme.users?.create("wile")
    print("   acme sees wile:   \(acme.users?.find("wile") ?? "nil")")
    print(
        "   globex sees wile: \(app.isolate(UserRepositoryKey.self, label: "globex").users?.find("wile") ?? "nil")"
    )

    print("\n6) Shut down the app — everything is rolled back in reverse order")
    await app.dispose()
}

try await runDemo()
