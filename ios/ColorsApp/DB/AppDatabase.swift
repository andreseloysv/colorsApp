// Base de datos GRDB de la app: DatabasePool (WAL) en Application Support/
// ColorsApp/colors.sqlite, migración v1 con las cuatro tablas sync-ready
// (PLAN §7) y v2 con los datos del recorte de sujeto en `scans` (SubjectKit) y
// la conversión del ajuste heredado `person_mask`. Reinstalar sobre el mismo
// bundle ID conserva el contenedor (es lo que mide LaunchCounter); los tests
// usan `inMemory()` o un directorio temporal.
//
// Las migraciones ya publicadas NO se editan: el iPhone del usuario tiene una
// base de datos creada por v1 (build Debug). Cada cambio de esquema es una
// migración nueva, probada con una base de datos creada solo con v1
// (DatabaseTests.testMigrationV1ToV2KeepsUnlocksAndFeedback).
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
        // Nunca se borra la base de datos por un cambio de esquema, tampoco en
        // Debug: la build del usuario es Debug y guarda sus desbloqueos y veredictos.
        migrator.eraseDatabaseOnSchemaChange = false
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
        migrator.registerMigration("v2") { db in
            try migrateV2(db, now: Date())
        }
        return migrator
    }

    /// v2: recorte de sujeto por scan y conversión del ajuste `person_mask`.
    ///
    /// - `scans` gana `subject_mode` (off|allPeople|largestPerson|selectedPerson),
    ///   `region_mode` (wholePerson|clothing), `adaptive_skin` (0/1),
    ///   `people_count`, `person_index` (índice en las personas ordenadas por
    ///   cobertura; NULL con allPeople/off o sin personas), `mask_steps` (JSON
    ///   `[MaskFallback.rawValue]`) y `mask_coverage` (REAL, 0...1). Nulas en los
    ///   scans anteriores a v2.
    /// - `person_mask` = "true" (máscara de persona de Vision de F6) pasa a
    ///   `subject_mode` = allPeople + `region_mode` = wholePerson, lo más parecido
    ///   a lo que hacía; "false" o ausente deja los nuevos valores por defecto
    ///   (sin filas: persona más grande + solo ropa + piel adaptativa). La clave
    ///   heredada se marca borrada (borrado suave, rev + 1, dirty).
    static func migrateV2(_ db: Database, now: Date) throws {
        try db.alter(table: "scans") { t in
            t.add(column: "subject_mode", .text)
            t.add(column: "region_mode", .text)
            t.add(column: "adaptive_skin", .integer)
            t.add(column: "people_count", .integer)
            t.add(column: "person_index", .integer)
            t.add(column: "mask_steps", .text)
            t.add(column: "mask_coverage", .real)
        }
        // SQL literal y no los registros de Records.swift: una migración publicada
        // no debe depender de tipos que evolucionan.
        guard let legacy = try String.fetchOne(db, sql: """
            SELECT value FROM settings WHERE key = 'person_mask' AND deleted_at IS NULL
            """) else { return }
        if legacy == "true" || legacy == "1" {
            for (key, value) in [("subject_mode", "allPeople"), ("region_mode", "wholePerson")] {
                try db.execute(sql: """
                    INSERT INTO settings (key, value, updated_at, deleted_at, rev, dirty)
                    VALUES (?, ?, ?, NULL, 1, 1)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at,
                        deleted_at = NULL, rev = settings.rev + 1, dirty = 1
                    """, arguments: [key, value, now])
            }
        }
        try db.execute(sql: """
            UPDATE settings SET deleted_at = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE key = 'person_mask'
            """, arguments: [now, now])
    }

    /// Identificadores de migración aplicados (para Ajustes/diagnóstico).
    func appliedMigrations() throws -> [String] {
        try writer.read { db in try Self.migrator.appliedIdentifiers(db).sorted() }
    }
}
