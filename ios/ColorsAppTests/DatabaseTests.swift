// GRDB: migraciones v1 + v2 + v3 (tablas, columnas sync-ready y del recorte, WAL),
// inserción de scan + unlock + feedback, observación de unlocks y UUIDv7
// monotónico. La migración v1 -> v2 -> v3 sobre una base creada solo con v1 está en
// SubjectDatabaseTests; aquí, v3 sobre bases creadas con v1 + v2 (la copia
// preliminar del iPhone): `person_mask` = true acaba en los valores por defecto nuevos.
import XCTest
import GRDB
import ColorEngine
import SubjectKit
@testable import ColorsApp

final class DatabaseTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-db-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleResult() -> AnalysisResult {
        AnalysisResult(
            swatches: [
                Swatch(lab: Lab(L: 94.33, a: -3.99, b: 33.45), r: 255, g: 239, b: 174, weight: 0.56),
                Swatch(lab: Lab(L: 54.56, a: 23.43, b: 51.57), r: 187, g: 113, b: 37, weight: 0.44),
            ],
            hits: [Hit(comboId: 3, score: 1.0e-12), Hit(comboId: 102, score: 11.418745355239), Hit(comboId: 31, score: 17.94)],
            ambiguous: false,
            hash: 0x1916605accb98536
        )
    }

    func testMigrationCreatesTablesInWALMode() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase.open(at: dir.appendingPathComponent("colors.sqlite"))
        XCTAssertEqual(try db.appliedMigrations(), ["v1", "v2", "v3", "v4"])
        try db.writer.read { db in
            for table in ["scans", "unlocks", "feedback", "settings"] {
                XCTAssertTrue(try db.tableExists(table), table)
                let columns = Set(try db.columns(in: table).map(\.name))
                for sync in ["updated_at", "deleted_at", "rev", "dirty"] {
                    XCTAssertTrue(columns.contains(sync), "\(table).\(sync)")
                }
            }
            let scanColumns = Set(try db.columns(in: "scans").map(\.name))
            XCTAssertTrue(scanColumns.isSuperset(of: ["id", "asset_local_id", "source", "top1", "top2", "top3", "scores",
                                                      "palette_json", "ambiguous", "engine_version", "dict_version", "scanned_at"]))
            XCTAssertTrue(scanColumns.isSuperset(of: ["subject_mode", "region_mode", "adaptive_skin", "people_count",
                                                      "person_index", "mask_steps", "mask_coverage"]))
            XCTAssertEqual(try db.primaryKey("unlocks").columns, ["combo_id"])
            XCTAssertEqual(try db.primaryKey("settings").columns, ["key"])
            let mode = try String.fetchOne(db, sql: "PRAGMA journal_mode")
            XCTAssertEqual(mode?.lowercased(), "wal")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("colors.sqlite").path))
    }

    func testInsertScanUnlockAndFeedback() async throws {
        let db = try AppDatabase.inMemory()
        let scans = ScanRepository(db)
        let unlocks = UnlockRepository(db)
        let feedback = FeedbackRepository(db)
        let settings = SettingsRepository(db)

        let now = Date(timeIntervalSince1970: 1_700_000_000) // pasado: no adelanta el reloj monotónico de UUIDv7
        let scan = ScanRecord.make(from: sampleResult(), source: .picker, assetLocalId: "asset-1", now: now)
        XCTAssertTrue(UUIDv7.isV7(try XCTUnwrap(UUID(uuidString: scan.id))))
        XCTAssertEqual(scan.id, scan.id.lowercased())
        XCTAssertEqual(scan.topIds, [3, 102, 31])
        XCTAssertEqual(scan.scoreValues.count, 3)
        XCTAssertEqual(scan.scoreValues[1], 11.418745355239, accuracy: 1e-12)
        XCTAssertEqual(scan.palette.map(\.hex), ["#ffefae", "#bb7125"])
        XCTAssertEqual(scan.engineVersion, colorEngineVersion)
        XCTAssertEqual(scan.dictVersion, dictionaryVersion)
        XCTAssertEqual(scan.rev, 1)
        XCTAssertTrue(scan.dirty)

        try await scans.insert(scan)
        let fetchedOptional = try await scans.fetch(id: scan.id)
        let fetched = try XCTUnwrap(fetchedOptional)
        XCTAssertEqual(fetched, scan)
        let scanCount = try await scans.count()
        XCTAssertEqual(scanCount, 1)
        let recent = try await scans.recent()
        XCTAssertEqual(recent.map(\.id), [scan.id])
        let withTop1 = try await scans.scans(withTop1: 3)
        XCTAssertEqual(withTop1.count, 1)

        // Unlock: nuevo la primera vez, repetido después.
        let firstUnlock = try await unlocks.unlock(comboId: 3, source: .picker, assetLocalId: "asset-1", scanId: scan.id, at: now)
        XCTAssertTrue(firstUnlock)
        let repeated = try await unlocks.unlock(comboId: 3, source: .picker, at: now)
        XCTAssertFalse(repeated)
        let fresh = try await unlocks.unlock(comboIds: [3, 102, 31], source: .manual)
        XCTAssertEqual(fresh, [102, 31])
        let unlockCount = try await unlocks.count()
        XCTAssertEqual(unlockCount, 3)
        let ids = try await unlocks.unlockedIds()
        XCTAssertEqual(ids, [3, 31, 102])
        let is3 = try await unlocks.isUnlocked(comboId: 3)
        XCTAssertTrue(is3)
        let is4 = try await unlocks.isUnlocked(comboId: 4)
        XCTAssertFalse(is4)
        let all = try await unlocks.all()
        let first = try XCTUnwrap(all.first)
        XCTAssertEqual(first.comboId, 3)
        XCTAssertEqual(first.scanId, scan.id)
        XCTAssertEqual(first.source, .picker)

        // Feedback.
        let fb = try await feedback.record(scanId: scan.id, verdict: .yes, at: now)
        XCTAssertTrue(UUIDv7.isV7(try XCTUnwrap(UUID(uuidString: fb.id))))
        _ = try await feedback.record(scanId: scan.id, verdict: .no, at: now.addingTimeInterval(1))
        let forScan = try await feedback.forScan(id: scan.id)
        XCTAssertEqual(forScan.map(\.verdict), [.no, .yes])
        let latest = try await feedback.latest(forScan: scan.id)
        XCTAssertEqual(latest?.verdict, .no)
        let counts = try await feedback.counts()
        XCTAssertEqual(counts.yes, 1)
        XCTAssertEqual(counts.no, 1)

        // Settings.
        let maskDefault = try await settings.bool(.personMask)
        XCTAssertFalse(maskDefault)
        try await settings.setBool(.personMask, true)
        let maskOn = try await settings.bool(.personMask)
        XCTAssertTrue(maskOn)
        try await settings.setInt(.initialScanCount, 200)
        let scanCountSetting = try await settings.int(.initialScanCount)
        XCTAssertEqual(scanCountSetting, 200)
        try await settings.set(.personMask, nil)
        let maskCleared = try await settings.get(.personMask)
        XCTAssertNil(maskCleared)

        // Borrado suave del scan: desaparece de recent y sube rev.
        try await scans.softDelete(id: scan.id, now: now.addingTimeInterval(2))
        let afterDelete = try await scans.count()
        XCTAssertEqual(afterDelete, 0)
        let deletedOptional = try await scans.fetch(id: scan.id)
        let deleted = try XCTUnwrap(deletedOptional)
        XCTAssertNotNil(deleted.deletedAt)
        XCTAssertEqual(deleted.rev, 2)

        // Reset de unlocks por origen.
        try await unlocks.deleteAll(source: .manual)
        let afterManual = try await unlocks.unlockedIds()
        XCTAssertEqual(afterManual, [3])
        try await unlocks.deleteAll()
        let afterAll = try await unlocks.count()
        XCTAssertEqual(afterAll, 0)
    }

    // MARK: Migración v3 (person_mask = true -> valores por defecto nuevos)

    /// Base creada con v1 (+ `person_mask` y datos de usuario) y migrada hasta `upTo`,
    /// como la dejaría la build correspondiente. `afterV2` corre sobre la base ya en v2
    /// (p. ej. el usuario cambia Ajustes con la build de v2).
    private func makeDatabase(personMask: String?, upTo: String, dir: URL,
                              afterV2: ((Database) throws -> Void)? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("colors.sqlite")
        var config = Configuration()
        config.journalMode = .wal
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppDatabase.migrator.migrate(pool, upTo: "v1")
        try pool.write { db in
            let t = "2026-09-10 10:00:00.000"
            try db.execute(sql: """
                INSERT INTO unlocks (combo_id, first_seen_at, source, asset_local_id, scan_id, updated_at, deleted_at, rev, dirty)
                VALUES (12, ?, 'camera', NULL, NULL, ?, NULL, 1, 1), (348, ?, 'library', NULL, NULL, ?, NULL, 1, 1)
                """, arguments: [t, t, t, t])
            try db.execute(sql: """
                INSERT INTO feedback (id, scan_id, verdict, created_at, updated_at, deleted_at, rev, dirty)
                VALUES ('0190a000-0000-7000-8000-0000000000f1', 'scan-1', 'no', ?, ?, NULL, 1, 1)
                """, arguments: [t, t])
            if let personMask {
                try db.execute(sql: """
                    INSERT INTO settings (key, value, updated_at, deleted_at, rev, dirty)
                    VALUES ('person_mask', ?, ?, NULL, 2, 0)
                    """, arguments: [personMask, t])
            }
        }
        if upTo != "v1" {
            try AppDatabase.migrator.migrate(pool, upTo: upTo)
        }
        if let afterV2 { try pool.write(afterV2) }
        XCTAssertEqual(try pool.read { db in try AppDatabase.migrator.appliedIdentifiers(db).sorted() },
                       upTo == "v1" ? ["v1"] : ["v1", "v2"])
        try pool.close()
        return url
    }

    private struct SettingsRow: Equatable {
        let value: String
        let deleted: Bool
        let rev: Int
        let dirty: Int
    }

    private func settingsRows(_ db: AppDatabase) throws -> [String: SettingsRow] {
        try db.writer.read { db in
            var out: [String: SettingsRow] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, value, deleted_at, rev, dirty FROM settings") {
                out[row["key"]] = SettingsRow(value: row["value"], deleted: (row["deleted_at"] as String?) != nil,
                                              rev: row["rev"], dirty: row["dirty"])
            }
            return out
        }
    }

    func testMigrationV3PersonMaskTrueFromV2DatabaseUsesNewDefaults() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeDatabase(personMask: "true", upTo: "v2", dir: dir)
        // Estado que dejó la build de v2: allPeople + wholePerson.
        let v2 = try DatabaseQueue(path: url.path)
        let v2Mode = try await v2.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'subject_mode' AND deleted_at IS NULL")
        }
        XCTAssertEqual(v2Mode, "allPeople")
        try v2.close()

        let db = try AppDatabase.open(at: url)
        XCTAssertEqual(try db.appliedMigrations(), ["v1", "v2", "v3", "v4"])
        let settings = SettingsRepository(db)
        let subject = try await settings.subjectSettings()
        XCTAssertEqual(subject, .default, "persona principal + solo ropa + piel adaptativa")
        XCTAssertEqual(subject.mode, .largestPerson)
        XCTAssertEqual(subject.region, .clothing)
        XCTAssertTrue(subject.adaptiveSkin)
        XCTAssertEqual(subject.subjectOptions, SubjectOptions.default)
        let rows = try settingsRows(db)
        XCTAssertEqual(rows["subject_mode"], SettingsRow(value: "allPeople", deleted: true, rev: 2, dirty: 1))
        XCTAssertEqual(rows["region_mode"], SettingsRow(value: "wholePerson", deleted: true, rev: 2, dirty: 1))
        XCTAssertEqual(rows["person_mask"]?.deleted, true)
        XCTAssertNil(rows["adaptive_skin"])
        let unlocked = try await UnlockRepository(db).unlockedIds()
        XCTAssertEqual(unlocked, [12, 348], "los desbloqueos se conservan")
        let counts = try await FeedbackRepository(db).counts()
        XCTAssertEqual(counts.no, 1)
        // Reabrir no vuelve a migrar.
        let again = try AppDatabase.open(at: url)
        XCTAssertEqual(try again.appliedMigrations(), ["v1", "v2", "v3", "v4"])
        XCTAssertEqual(try settingsRows(again), rows)
        print("MIGRACION | v1+v2 (person_mask=true) -> v3 | subject_mode \(subject.mode.rawValue) | region_mode \(subject.region.rawValue) | piel \(subject.adaptiveSkin) | unlocks \(unlocked.count) | feedback \(counts.no + counts.yes)")
    }

    func testMigrationV3KeepsSettingsChosenAfterV2() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Con la build de v2 el usuario volvió a elegir «Todas las personas» en Ajustes (otra fecha)
        // y no tocó la región: v3 respeta su elección y solo corrige lo que escribió v2.
        let url = try makeDatabase(personMask: "true", upTo: "v2", dir: dir) { db in
            try db.execute(sql: """
                UPDATE settings SET value = 'allPeople', updated_at = '2026-09-16 09:30:00.000', rev = rev + 1, dirty = 1
                WHERE key = 'subject_mode'
                """)
        }
        let db = try AppDatabase.open(at: url)
        let subject = try await SettingsRepository(db).subjectSettings()
        XCTAssertEqual(subject.mode, .allPeople, "elección del usuario posterior a v2")
        XCTAssertEqual(subject.region, .clothing, "la región que escribió v2 vuelve al defecto")
        XCTAssertTrue(subject.adaptiveSkin)
        let rows = try settingsRows(db)
        XCTAssertEqual(rows["subject_mode"], SettingsRow(value: "allPeople", deleted: false, rev: 2, dirty: 1))
        XCTAssertEqual(rows["region_mode"]?.deleted, true)
        print("MIGRACION | v1+v2 (person_mask=true) + Ajustes allPeople -> v3 | subject_mode \(subject.mode.rawValue) | region_mode \(subject.region.rawValue) | piel \(subject.adaptiveSkin)")
    }

    func testMigrationV3CasesTable() async throws {
        // Todas las combinaciones de origen: v1 -> (v2 ->) v3 con person_mask true / false / ausente
        // y v1 + v2 con elecciones explícitas del usuario, que v3 no toca.
        var lines = ["MIGRACION | origen | person_mask | subject_mode | region_mode | adaptive_skin | migraciones"]
        for (upTo, mask) in [("v1", "true"), ("v1", "false"), ("v1", nil), ("v2", "true"), ("v2", "1"), ("v2", "false"), ("v2", nil)] as [(String, String?)] {
            let dir = tempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = try makeDatabase(personMask: mask, upTo: upTo, dir: dir)
            let db = try AppDatabase.open(at: url)
            let subject = try await SettingsRepository(db).subjectSettings()
            XCTAssertEqual(subject, .default, "\(upTo) person_mask=\(mask ?? "ausente")")
            lines.append("MIGRACION | \(upTo) | \(mask ?? "ausente") | \(subject.mode.rawValue) | \(subject.region.rawValue) | \(subject.adaptiveSkin) | \(try db.appliedMigrations().joined(separator: ","))")
        }
        // Una base v2 sin person_mask en la que el usuario eligió allPeople + wholePerson: intacta.
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeDatabase(personMask: nil, upTo: "v2", dir: dir) { db in
            for (key, value) in [("subject_mode", "allPeople"), ("region_mode", "wholePerson")] {
                try db.execute(sql: "INSERT INTO settings (key, value, updated_at, deleted_at, rev, dirty) VALUES (?, ?, '2026-09-16 08:00:00.000', NULL, 1, 1)",
                               arguments: [key, value])
            }
        }
        let db = try AppDatabase.open(at: url)
        let chosen = try await SettingsRepository(db).subjectSettings()
        XCTAssertEqual(chosen.mode, .allPeople)
        XCTAssertEqual(chosen.region, .wholePerson)
        lines.append("MIGRACION | v2 + Ajustes (sin person_mask) | ausente | \(chosen.mode.rawValue) | \(chosen.region.rawValue) | \(chosen.adaptiveSkin) | \(try db.appliedMigrations().joined(separator: ","))")
        print(lines.joined(separator: "\n"))
    }

    func testUnlockObservationEmitsChanges() async throws {
        let db = try AppDatabase.inMemory()
        let unlocks = UnlockRepository(db)
        let observation = unlocks.observeUnlockedIds()

        let collected = Task { () -> [Set<Int>] in
            var values: [Set<Int>] = []
            for try await ids in observation {
                values.append(ids)
                if ids.count >= 2 { break }
            }
            return values
        }
        // Espera al valor inicial antes de escribir.
        try await Task.sleep(nanoseconds: 200_000_000)
        try await unlocks.unlock(comboId: 5, source: .manual)
        try await unlocks.unlock(comboId: 7, source: .manual)
        let values = try await collected.value
        XCTAssertEqual(values.first, [])
        XCTAssertEqual(values.last, [5, 7])
        XCTAssertGreaterThanOrEqual(values.count, 2)

        // Contador observado.
        var counts: [Int] = []
        for try await n in unlocks.observeCount() {
            counts.append(n)
            break
        }
        XCTAssertEqual(counts, [2])
    }

    func testScanObservation() async throws {
        let db = try AppDatabase.inMemory()
        let scans = ScanRepository(db)
        let scan = ScanRecord.make(from: sampleResult(), source: .camera)
        try await scans.insert(scan)
        var first: [ScanRecord] = []
        for try await recent in scans.observeRecent(limit: 10) {
            first = recent
            break
        }
        XCTAssertEqual(first.map(\.id), [scan.id])
    }

    func testUUIDv7IsMonotonicAndWellFormed() throws {
        let n = 5000
        var previous = ""
        var seen = Set<String>()
        for _ in 0..<n {
            let uuid = UUIDv7.generate()
            let s = uuid.uuidString.lowercased()
            XCTAssertTrue(UUIDv7.isV7(uuid))
            XCTAssertEqual(s[s.index(s.startIndex, offsetBy: 14)], "7")
            XCTAssertTrue("89ab".contains(s[s.index(s.startIndex, offsetBy: 19)]))
            XCTAssertGreaterThan(s, previous) // orden lexicográfico == orden temporal
            XCTAssertTrue(seen.insert(s).inserted)
            previous = s
        }
        XCTAssertEqual(seen.count, n)
        // Timestamp recuperable: id recién generado ≈ ahora (±1 s).
        let nowId = UUIDv7.generate()
        let nowTs = try XCTUnwrap(UUIDv7.timestamp(of: nowId))
        XCTAssertEqual(nowTs.timeIntervalSinceNow, 0, accuracy: 1.0)
        // Fecha fija en los 48 bits altos (constructor determinista, sin el guardián monotónico).
        let fixed = Date(timeIntervalSince1970: 1_700_000_000.123)
        let u = UUIDv7.make(milliseconds: UUIDv7.milliseconds(fixed), counter: 0x0ABC)
        XCTAssertEqual(u.uuidString.lowercased().prefix(18), "018bcfe5-687b-7abc")
        let ts = try XCTUnwrap(UUIDv7.timestamp(of: u))
        XCTAssertEqual(ts.timeIntervalSince1970, fixed.timeIntervalSince1970, accuracy: 0.002)
        // Reloj hacia atrás: el generador no retrocede (id posterior sigue siendo mayor).
        let back = UUIDv7.generate(now: fixed)
        XCTAssertGreaterThan(back.uuidString.lowercased(), previous)
        XCTAssertNil(UUIDv7.timestamp(of: UUID()))
        XCTAssertFalse(UUIDv7.isV7(UUID()))
    }
}
