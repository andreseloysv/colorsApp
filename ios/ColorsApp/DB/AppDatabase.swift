// Base de datos GRDB de la app: DatabasePool (WAL) en Application Support/
// ColorsApp/colors.sqlite, migración v1 con las cuatro tablas sync-ready
// (PLAN §7), v2 con los datos del recorte de sujeto en `scans` (SubjectKit),
// la conversión del ajuste heredado `person_mask`, v3, que corrige esa
// conversión (`person_mask` = true acaba en los valores por defecto nuevos), y
// v4, que añade la paleta por prenda y la versión de la política de análisis
// (`AnalysisPolicy`) para saber qué scans hay que volver a analizar.
// Reinstalar sobre el mismo bundle ID conserva el contenedor (es lo que mide
// LaunchCounter); los tests usan `inMemory()` o un directorio temporal.
//
// Las migraciones ya publicadas NO se editan: el iPhone del usuario tiene una
// base de datos creada por v1 (build Debug) y la copia preliminar trae v2. Cada
// cambio de esquema o de datos es una migración nueva, probada con una base de
// datos creada solo con v1 (SubjectDatabaseTests) y con una creada con v1 + v2
// (DatabaseTests, migración v3).
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
        migrator.registerMigration("v3") { db in
            try migrateV3(db, now: Date())
        }
        migrator.registerMigration("v4") { db in
            try migrateV4(db)
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
    ///   a lo que hacía (v3 lo corrige: acaba en los valores por defecto nuevos); "false" o ausente deja los nuevos valores por defecto
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

    /// v3: `person_mask` = true debe acabar en los valores por defecto nuevos (persona
    /// principal + solo ropa + piel adaptativa, decisión del usuario, CONTEXT §10), no en
    /// allPeople + wholePerson como hizo v2 (issue minor de la verificación de 2026-09-15).
    ///
    /// v2 ya está publicada (la copia preliminar del iPhone la trae), así que no se edita:
    /// v3 borra (borrado suave, rev + 1, dirty) las filas `subject_mode` = allPeople y
    /// `region_mode` = wholePerson que escribió la conversión de v2, reconocibles porque su
    /// `updated_at` es exactamente el `deleted_at` de `person_mask` (el mismo `now` de v2) y
    /// no han cambiado desde entonces. Si el usuario eligió después esos modos en Ajustes,
    /// `updated_at` es otro y se respetan. `adaptive_skin` no lo tocó v2 y no se toca.
    /// Una base creada sin v2 (v1 -> v2 -> v3 en la misma apertura) acaba igual.
    static func migrateV3(_ db: Database, now: Date) throws {
        try db.execute(sql: """
            UPDATE settings
            SET deleted_at = ?, updated_at = ?, rev = rev + 1, dirty = 1
            WHERE deleted_at IS NULL
              AND ((key = 'subject_mode' AND value = 'allPeople') OR (key = 'region_mode' AND value = 'wholePerson'))
              AND updated_at = (SELECT pm.deleted_at FROM settings pm
                                WHERE pm.key = 'person_mask' AND pm.deleted_at IS NOT NULL
                                  AND pm.value IN ('true', '1'))
            """, arguments: [now, now])
    }

    /// v4 (aditiva): paleta por prenda (ADR-011, CONTEXT §13) y versión de la política de análisis.
    ///
    /// `scans` gana tres columnas, todas NULL en los scans anteriores (nada se reescribe):
    /// - `garments_json`: JSON `[GarmentEntry]` con el color de cada prenda (región 1 arriba,
    ///   2 abajo, 3 prenda entera), su peso, la cuota de su región y los clusters agrupados;
    ///   NULL = el scan salió del camino clásico (sin pose, sin mapa de regiones).
    /// - `garment_regions`: número de regiones del mapa que recibió el motor (2 con pose;
    ///   NULL sin mapa). No se guarda el mapa de píxeles: se recalcula desde la foto.
    /// - `engine_policy_version`: `AnalysisPolicy.current` cuando se analizó (NULL = anterior a
    ///   v4). La app compara ese número, `engine_version` y `dict_version` con los actuales
    ///   (`AnalysisPolicy.needsReanalysis`) para volver a analizar los scans viejos al abrirlos;
    ///   la lógica de re-análisis en las vistas la hace el equipo de interfaz.
    ///
    /// Las migraciones publicadas (v1, v2 y v3) no se tocan: los datos que escribieron se
    /// conservan tal cual (lo comprueba GarmentDatabaseTests con bases creadas en v1, v2 y v3).
    static func migrateV4(_ db: Database) throws {
        try db.alter(table: "scans") { t in
            t.add(column: "garments_json", .text)
            t.add(column: "garment_regions", .integer)
            t.add(column: "engine_policy_version", .integer)
        }
    }

    /// Identificadores de migración aplicados (para Ajustes/diagnóstico).
    func appliedMigrations() throws -> [String] {
        try writer.read { db in try Self.migrator.appliedIdentifiers(db).sorted() }
    }
}
