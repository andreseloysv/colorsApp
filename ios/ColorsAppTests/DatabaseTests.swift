// GRDB: migraciones v1 + v2 (tablas, columnas sync-ready y del recorte, WAL),
// inserción de scan + unlock + feedback, observación de unlocks y UUIDv7
// monotónico. La migración v1 -> v2 sobre una base creada solo con v1 está en
// SubjectDatabaseTests.
import XCTest
import GRDB
import ColorEngine
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
        XCTAssertEqual(try db.appliedMigrations(), ["v1", "v2"])
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
