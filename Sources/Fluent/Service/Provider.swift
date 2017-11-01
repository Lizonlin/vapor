import Async
import Dispatch
import Service
import SQLite

/// Registers Fluent related services.
public final class FluentProvider: Provider {
    /// See Provider.repositoryName
    public static var repositoryName: String = "fluent"

    /// Creates a new Fluent provider.
    public init() { }

    /// See Provider.register()
    public func register(_ services: inout Services) throws {
        services.register { container -> SQLiteDatabase in
            let storage = try container.make(SQLiteStorage.self, for: SQLiteDatabase.self)
            return SQLiteDatabase(storage: storage)
        }

//        services.register { container -> DatabaseMiddleware in
//            let databases = try container.make(Databases.self, for: DatabaseMiddleware.self)
//            return DatabaseMiddleware(databases: databases)
//        }

        services.register { container -> Databases in
            let config = try container.make(DatabaseConfig.self, for: FluentProvider.self)
            var databases: [String: Any] = [:]
            for (id, lazyDatabase) in config.databases {
                let db = try lazyDatabase(container)
                if let supports = db as? SupportsLogging, let logger = config.logging[id] {
                    logger.dbID = id
                    supports.enableLogging(using: logger)
                }
                databases[id] = db
            }
            return Databases(storage: databases)
        }
    }

    /// See Provider.boot()
    public func boot(_ container: Container) throws {
        let config = try container.make(MigrationConfig.self, for: FluentProvider.self)
        let databases = try container.make(Databases.self, for: FluentProvider.self)

        let migrationQueue = DispatchQueue(label: "codes.vapor.fluent.migration")

        var results: [Future<Void>] = []

        for (uid, config) in config.storage {
            print("Migrating \(uid) DB")
            let result = config.migrate(using: databases, on: migrationQueue)
            results.append(result)
        }

        // FIXME: should this be nonblocking?
        try results.flatten().blockingAwait()

        print("Migrations complete")
    }
}
