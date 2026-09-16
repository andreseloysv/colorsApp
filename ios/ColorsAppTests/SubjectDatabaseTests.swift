// Migraciones v2 + v3 sobre una base de datos creada SOLO con v1 (la del iPhone del
// usuario, build Debug): conservan unlocks, feedback, scans y ajustes; añaden las
// columnas del recorte; convierten `person_mask` (true, false o ausente -> nuevos
// defectos: persona principal + solo ropa + piel; v2 lo pasaba a allPeople +
// wholePerson y v3 lo corrige) y los ajustes del recorte y del umbral de
// desbloqueo se leen y escriben con sus valores por defecto.
import XCTest
import GRDB
import ColorEngine
import SubjectKit
@testable import ColorsApp

final class SubjectDatabaseTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Crea colors.sqlite con la migración v1 tal cual (sin v2) y filas escritas
    /// por SQL como las dejaría la build anterior. `personMask`: valor de la clave
    /// heredada o nil para no escribirla.
    private func makeV1Database(personMask: String?) throws -> URL {
        let url = dir.appendingPathComponent("colors.sqlite")
        var config = Configuration()
        config.journalMode = .wal
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppDatabase.migrator.migrate(pool, upTo: "v1")
        try pool.write { db in
            let t = "2026-09-10 10:00:00.000"
            try db.execute(sql: """
                INSERT INTO scans (id, asset_local_id, source, top1, top2, top3, scores, palette_json, ambiguous,
                                   engine_version, dict_version, scanned_at, updated_at, deleted_at, rev, dirty)
                VALUES ('0190a000-0000-7000-8000-000000000001', 'asset-v1', 'camera', 12, 178, 3, '[0.5,2,3]',
                        '[{"hex":"#c5a56e","lab":[70,3,33],"rgb":[197,165,110],"weight":1}]', 0, '0.1.0', 'fd95ac692777',
                        ?, ?, NULL, 1, 1)
                """, arguments: [t, t])
            try db.execute(sql: """
                INSERT INTO unlocks (combo_id, first_seen_at, source, asset_local_id, scan_id, updated_at, deleted_at, rev, dirty)
                VALUES (12, ?, 'camera', 'asset-v1', '0190a000-0000-7000-8000-000000000001', ?, NULL, 1, 1),
                       (200, ?, 'library', NULL, NULL, ?, NULL, 1, 1)
                """, arguments: [t, t, t, t])
            try db.execute(sql: """
                INSERT INTO feedback (id, scan_id, verdict, created_at, updated_at, deleted_at, rev, dirty)
                VALUES ('0190a000-0000-7000-8000-0000000000f1', '0190a000-0000-7000-8000-000000000001', 'yes', ?, ?, NULL, 1, 1)
                """, arguments: [t, t])
            try db.execute(sql: """
                INSERT INTO settings (key, value, updated_at, deleted_at, rev, dirty)
                VALUES ('initial_scan_done', 'true', ?, NULL, 1, 1)
                """, arguments: [t])
            if let personMask {
                try db.execute(sql: """
                    INSERT INTO settings (key, value, updated_at, deleted_at, rev, dirty)
                    VALUES ('person_mask', ?, ?, NULL, 3, 0)
                    """, arguments: [personMask, t])
            }
        }
        XCTAssertEqual(try pool.read { db in try AppDatabase.migrator.appliedIdentifiers(db) }, ["v1"])
        try pool.close()
        return url
    }

    func testMigrationV1ToV2KeepsUnlocksAndFeedback() async throws {
        let url = try makeV1Database(personMask: nil)
        let db = try AppDatabase.open(at: url)
        XCTAssertEqual(try db.appliedMigrations(), ["v1", "v2", "v3", "v4"])

        let unlocks = UnlockRepository(db)
        let ids = try await unlocks.unlockedIds()
        XCTAssertEqual(ids, [12, 200], "los desbloqueos de v1 siguen ahí")
        let record = try await unlocks.record(comboId: 12)
        XCTAssertEqual(record?.scanId, "0190a000-0000-7000-8000-000000000001")

        let feedback = FeedbackRepository(db)
        let latest = try await feedback.latest(forScan: "0190a000-0000-7000-8000-000000000001")
        XCTAssertEqual(latest?.verdict, .yes)
        let counts = try await feedback.counts()
        XCTAssertEqual(counts.yes, 1)

        let scans = ScanRepository(db)
        let oldOptional = try await scans.fetch(id: "0190a000-0000-7000-8000-000000000001")
        let old = try XCTUnwrap(oldOptional)
        XCTAssertEqual(old.topIds, [12, 178, 3])
        XCTAssertNil(old.subjectMode)
        XCTAssertNil(old.peopleCount)
        XCTAssertNil(old.maskCoverage)
        XCTAssertEqual(old.maskStepValues, [])

        let settings = SettingsRepository(db)
        let done = try await settings.bool(.initialScanDone)
        XCTAssertTrue(done)
        let subject = try await settings.subjectSettings()
        XCTAssertEqual(subject, .default, "sin person_mask: nuevos valores por defecto")

        // Un scan nuevo guarda y relee las columnas del recorte.
        let result = AnalysisResult(swatches: [Swatch(lab: Lab(L: 50, a: 0, b: 0), r: 119, g: 119, b: 119, weight: 1)],
                                    hits: [Hit(comboId: 5, score: 1)], ambiguous: false, hash: 1)
        let info = ScanSubjectInfo(mode: .selectedPerson, region: .clothing, adaptiveSkin: true, peopleCount: 3,
                                   personIndex: 2, steps: [.poseRegions, .skinGuard], maskCoverage: 0.125)
        let scan = ScanRecord.make(from: result, source: .picker, subject: info, now: Date(timeIntervalSince1970: 1_700_000_000))
        try await scans.insert(scan)
        let backOptional = try await scans.fetch(id: scan.id)
        let back = try XCTUnwrap(backOptional)
        XCTAssertEqual(back, scan)
        XCTAssertEqual(back.subjectMode, "selectedPerson")
        XCTAssertEqual(back.regionMode, "clothing")
        XCTAssertEqual(back.adaptiveSkin, true)
        XCTAssertEqual(back.peopleCount, 3)
        XCTAssertEqual(back.personIndex, 2)
        XCTAssertEqual(back.maskStepValues, [.poseRegions, .skinGuard])
        XCTAssertEqual(back.maskSteps, "[\"poseRegions\",\"skinGuard\"]")
        XCTAssertEqual(back.maskCoverage ?? 0, 0.125, accuracy: 1e-12)
        try await db.writer.read { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT typeof(mask_coverage) AS t, adaptive_skin FROM scans WHERE id = ?",
                                                 arguments: [scan.id]))
            XCTAssertEqual(row["t"] as String, "real")
            XCTAssertEqual(row["adaptive_skin"] as Int, 1)
        }

        // Reabrir no vuelve a migrar ni borra nada (eraseDatabaseOnSchemaChange = false).
        let again = try AppDatabase.open(at: url)
        XCTAssertEqual(try again.appliedMigrations(), ["v1", "v2", "v3", "v4"])
        let againCount = try await UnlockRepository(again).count()
        XCTAssertEqual(againCount, 2)
        XCTAssertFalse(AppDatabase.migrator.eraseDatabaseOnSchemaChange)
    }

    func testPersonMaskTrueMigratesToNewDefaults() async throws {
        let db = try AppDatabase.open(at: try makeV1Database(personMask: "true"))
        let settings = SettingsRepository(db)
        let subject = try await settings.subjectSettings()
        XCTAssertEqual(subject.mode, .largestPerson, "v3: persona principal, no allPeople")
        XCTAssertEqual(subject.region, .clothing, "v3: solo ropa, no wholePerson")
        XCTAssertTrue(subject.adaptiveSkin, "la piel adaptativa conserva su defecto")
        XCTAssertEqual(subject.unlockMaxScore, 12.0)
        let legacy = try await settings.get(.personMask)
        XCTAssertNil(legacy, "la clave heredada queda borrada (borrado suave)")
        try await db.writer.read { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT deleted_at, rev, dirty FROM settings WHERE key = 'person_mask'"))
            XCTAssertNotNil(row["deleted_at"] as String?)
            XCTAssertEqual(row["rev"] as Int, 4)
            XCTAssertEqual(row["dirty"] as Int, 1)
            let mode = try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'subject_mode' AND deleted_at IS NULL")
            XCTAssertNil(mode, "v3 borra (suave) el allPeople que escribió v2")
        }
    }

    func testPersonMaskFalseKeepsNewDefaults() async throws {
        let db = try AppDatabase.open(at: try makeV1Database(personMask: "false"))
        let settings = SettingsRepository(db)
        let subject = try await settings.subjectSettings()
        XCTAssertEqual(subject, SubjectSettings(mode: .largestPerson, region: .clothing, adaptiveSkin: true, unlockMaxScore: 12))
        let legacy = try await settings.get(.personMask)
        XCTAssertNil(legacy)
        let mode = try await settings.get(.subjectMode)
        XCTAssertNil(mode, "false no escribe claves nuevas: se usan los defectos")
    }

    func testSubjectSettingsReadWriteAndScanPolicy() async throws {
        let db = try AppDatabase.inMemory()
        let settings = SettingsRepository(db)
        let initial = try await settings.subjectSettings()
        XCTAssertEqual(initial, .default)
        XCTAssertEqual(initial.subjectOptions, SubjectOptions.default)
        XCTAssertEqual(initial.scanPolicy().unlockMaxScore, ScanPolicy.defaultUnlockMaxScore)

        try await settings.set(.subjectMode, "off")
        try await settings.set(.regionMode, "wholePerson")
        try await settings.setBool(.adaptiveSkin, false)
        try await settings.setDouble(.unlockMaxScore, 7.5)
        var changed = try await settings.subjectSettings()
        XCTAssertEqual(changed, SubjectSettings(mode: .off, region: .wholePerson, adaptiveSkin: false, unlockMaxScore: 7.5))
        XCTAssertEqual(changed.subjectOptions.mode, .off)
        XCTAssertEqual(changed.scanPolicy().unlockMaxScore, 7.5)

        // Valores ilegibles o que no son ajustes (selectedPerson) cuentan como ausentes.
        try await settings.set(.subjectMode, "selectedPerson")
        try await settings.set(.unlockMaxScore, "nan")
        changed = try await settings.subjectSettings()
        XCTAssertEqual(changed.mode, .largestPerson)
        XCTAssertEqual(changed.unlockMaxScore, 12.0)

        // Ajustes escribe solo lo que cambia.
        await AjustesForm.persist(old: .default, new: SubjectSettings(mode: .allPeople), settings: settings)
        let mode = try await settings.get(.subjectMode)
        XCTAssertEqual(mode, "allPeople")
        XCTAssertEqual(SubjectSettings.settingsModes.map(\.settingsTitle), ["Desactivado", "Todas las personas", "Persona principal"])
        XCTAssertEqual(RegionMode.allCases.map(\.settingsTitle), ["Persona completa", "Solo ropa"])
    }
}
