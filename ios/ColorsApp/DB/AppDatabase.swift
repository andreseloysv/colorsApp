// Base de datos GRDB de la app: DatabasePool (WAL) en Application Support/
// ColorsApp/colors.sqlite y migración v1 con las cuatro tablas sync-ready
// (PLAN §7). Reinstalar sobre el mismo bundle ID conserva el contenedor (es lo
// que mide LaunchCounter); los tests usan `inMemory()` o un directorio temporal.
import Foundation
import GRDB

final class AppDatabase: Sendable {
    static let fileName = "colors.sqlite"
    static let directoryName = "ColorsApp"

    /// DatabasePool en disco o DatabaseQueue en memoria (tests).
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// URL por defecto: Application Support/ColorsApp/colors.sqlite.
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true).appendingPathComponent(fileName)
    }

    /// Abre (o crea) la base de datos en `url` (por defecto `defaultURL`) como
    /// DatabasePool en modo WAL, creando el directorio si falta.
    static func open(at url: URL = defaultURL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.journalMode = .wal
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(writer: pool)
    }

    /// Base de datos en memoria (tests y previews).
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    // MARK: Migraciones

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // Solo en Debug: si el esquema cambia durante el desarrollo se recrea.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1") { db in
            try db.create(table: "scans") { t in
                t.primaryKey("id", .text)
                t.column("asset_local_id", .text)
                t.column("source", .text).notNull()
                t.column("top1", .integer)
                t.column("top2", .integer)
                t.column("top3", .integer)
                t.column("scores", .text).notNull().defaults(to: "[]")
                t.column("palette_json", .text).notNull().defaults(to: "[]")
                t.column("ambiguous", .integer).notNull().defaults(to: 0)
                t.column("engine_version", .text).notNull()
                t.column("dict_version", .text).notNull()
                t.column("scanned_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
                t.column("rev", .integer).notNull().defaults(to: 1)
                t.column("dirty", .integer).notNull().defaults(to: 1)
            }
            try db.create(indexOn: "scans", columns: ["scanned_at"])
            try db.create(indexOn: "scans", columns: ["asset_local_id"])

            try db.create(table: "unlocks") { t in
                t.primaryKey("combo_id", .integer)
                t.column("first_seen_at", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("asset_local_id", .text)
                t.column("scan_id", .text)
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
                t.column("rev", .integer).notNull().defaults(to: 1)
                t.column("dirty", .integer).notNull().defaults(to: 1)
            }

            try db.create(table: "feedback") { t in
                t.primaryKey("id", .text)
                t.column("scan_id", .text).notNull()
                t.column("verdict", .text).notNull().check { ["yes", "no"].contains($0) }
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
                t.column("rev", .integer).notNull().defaults(to: 1)
                t.column("dirty", .integer).notNull().defaults(to: 1)
            }
            try db.create(indexOn: "feedback", columns: ["scan_id"])

            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
                t.column("rev", .integer).notNull().defaults(to: 1)
                t.column("dirty", .integer).notNull().defaults(to: 1)
            }
        }
        return migrator
    }

    /// Identificadores de migración aplicados (para Ajustes/diagnóstico).
    func appliedMigrations() throws -> [String] {
        try writer.read { db in try Self.migrator.appliedIdentifiers(db).sorted() }
    }
}
