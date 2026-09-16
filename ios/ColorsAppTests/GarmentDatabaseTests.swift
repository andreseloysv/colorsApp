// Migración v4 (aditiva): paleta por prenda y versión de la política de análisis.
//
// - Una base creada con v1 + v2 + v3 (la que tendría un iPhone con la build anterior), con scans,
//   unlocks, feedback y ajustes, se abre con v4: nada se pierde, las columnas nuevas quedan NULL
//   y los scans viejos piden re-análisis (AnalysisPolicy.needsReanalysis).
// - Un scan nuevo guarda los colores por prenda (región, peso, cuota, clusters agrupados) y la
//   versión de la política; al releerlo salen igual.
import XCTest
import GRDB
import ColorEngine
import SubjectKit
@testable import ColorsApp

final class GarmentDatabaseTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-garm-\(UUID().uuidString)", isDirectory: true)
    }

    private func result() -> AnalysisResult {
        AnalysisResult(
            swatches: [
                Swatch(lab: Lab(L: 79.5, a: 8.1, b: 0.4), r: 0xdd, g: 0xc0, b: 0xc8, weight: 0.6),
                Swatch(lab: Lab(L: 17.8, a: -0.3, b: 0.1), r: 0x2b, g: 0x2c, b: 0x2c, weight: 0.4),
            ],
            hits: [Hit(comboId: 27, score: 21.55), Hit(comboId: 337, score: 22.1)],
            ambiguous: false,
            hash: 0x0123_4567_89ab_cdef
        )
    }

    private func garments() -> ScanGarmentInfo {
        ScanGarmentInfo(garments: [
            GarmentSwatch(swatch: Swatch(lab: Lab(L: 79.5, a: 8.1, b: 0.4), r: 0xdd, g: 0xc0, b: 0xc8, weight: 0.6),
                          region: .lower, regionShare: 0.45, mergedClusterCount: 4),
            GarmentSwatch(swatch: Swatch(lab: Lab(L: 17.8, a: -0.3, b: 0.1), r: 0x2b, g: 0x2c, b: 0x2c, weight: 0.4),
                          region: .upper, regionShare: 0.55, mergedClusterCount: 2),
        ], regionCount: 2)
    }

    /// Base creada con v1 + v2 + v3 y datos de usuario, como la dejaría la build anterior.
    private func makeV3Database(dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("colors.sqlite")
        var config = Configuration()
        config.journalMode = .wal
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppDatabase.migrator.migrate(pool, upTo: "v3")
        try pool.write { db in
            let t = "2026-09-12 08:30:00.000"
            try db.execute(sql: """
                INSERT INTO scans (id, asset_local_id, source, top1, top2, top3, scores, palette_json, ambiguous,
                                   engine_version, dict_version, scanned_at, updated_at, deleted_at, rev, dirty,
                                   subject_mode, region_mode, adaptive_skin, people_count, person_index, mask_steps,
                                   mask_coverage)
                VALUES ('0190a000-0000-7000-8000-00000000ab01', 'asset-1', 'camera', 67, 337, 27, '[17.18,19.56,21.56]',
                        '[{"hex":"#222524","lab":[14.2,-0.4,0.3],"rgb":[34,37,36],"weight":0.39}]', 0, '0.1.0',
                        'fd95ac692777', ?, ?, NULL, 3, 0, 'largestPerson', 'clothing', 1, 2, 0,
                        '["poseRegions","skinExcluded"]', 0.21)
                """, arguments: [t, t])
            try db.execute(sql: """
                INSERT INTO unlocks (combo_id, first_seen_at, source, asset_local_id, scan_id, updated_at, deleted_at, rev, dirty)
                VALUES (67, ?, 'camera', 'asset-1', '0190a000-0000-7000-8000-00000000ab01', ?, NULL, 1, 1)
                """, arguments: [t, t])
            try db.execute(sql: """
                INSERT INTO feedback (id, scan_id, verdict, created_at, updated_at, deleted_at, rev, dirty)
                VALUES ('0190a000-0000-7000-8000-00000000fe01', '0190a000-0000-7000-8000-00000000ab01', 'no', ?, ?, NULL, 1, 1)
                """, arguments: [t, t])
            try db.execute(sql: """
                INSERT INTO settings (key, value, updated_at, deleted_at, rev, dirty)
                VALUES ('subject_mode', 'allPeople', ?, NULL, 4, 1)
                """, arguments: [t])
        }
        XCTAssertEqual(try pool.read { db in try AppDatabase.migrator.appliedIdentifiers(db).sorted() },
                       ["v1", "v2", "v3"])
        try pool.close()
        return url
    }

    func testMigrationV4KeepsV3DataAndAddsNullColumns() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makeV3Database(dir: dir)
        let db = try AppDatabase.open(at: url)
        XCTAssertEqual(try db.appliedMigrations(), ["v1", "v2", "v3", "v4"])
        let columns = try await db.writer.read { db in Set(try db.columns(in: "scans").map(\.name)) }
        XCTAssertTrue(columns.isSuperset(of: ["garments_json", "garment_regions", "engine_policy_version"]))
        // Los datos de v1-v3 siguen ahí, con sus columnas sync-ready intactas.
        let scans = ScanRepository(db)
        let fetched = try await scans.fetch(id: "0190a000-0000-7000-8000-00000000ab01")
        let scan = try XCTUnwrap(fetched)
        XCTAssertEqual(scan.topIds, [67, 337, 27])
        XCTAssertEqual(scan.scoreValues, [17.18, 19.56, 21.56])
        XCTAssertEqual(scan.palette.first?.hex, "#222524")
        XCTAssertEqual(scan.subjectMode, "largestPerson")
        XCTAssertEqual(scan.maskStepValues, [.poseRegions, .skinExcluded])
        XCTAssertEqual(scan.maskCoverage, 0.21)
        XCTAssertEqual(scan.rev, 3)
        XCTAssertFalse(scan.dirty)
        // Columnas nuevas vacías y scan marcado para re-análisis.
        XCTAssertNil(scan.garmentsJson)
        XCTAssertNil(scan.garmentRegions)
        XCTAssertNil(scan.enginePolicyVersion)
        XCTAssertTrue(scan.garmentColors.isEmpty)
        XCTAssertTrue(scan.needsReanalysis)
        let pending = try await scans.needingReanalysis()
        XCTAssertEqual(pending.map(\.id), [scan.id])
        // Unlocks, feedback y ajustes conservados.
        let unlocked = try await UnlockRepository(db).unlockedIds()
        XCTAssertEqual(unlocked, [67])
        let verdict = try await FeedbackRepository(db).latest(forScan: scan.id)?.verdict
        XCTAssertEqual(verdict, .no)
        let mode = try await SettingsRepository(db).get(.subjectMode)
        XCTAssertEqual(mode, "allPeople")
        // Reabrir no vuelve a migrar ni cambia nada.
        let again = try AppDatabase.open(at: url)
        XCTAssertEqual(try again.appliedMigrations(), ["v1", "v2", "v3", "v4"])
        let count = try await ScanRepository(again).count()
        XCTAssertEqual(count, 1)
    }

    func testGarmentColorsAndPolicyRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let scans = ScanRepository(db)
        let subject = ScanSubjectInfo(mode: .largestPerson, region: .clothing, adaptiveSkin: true, peopleCount: 1,
                                      personIndex: 0, steps: [.poseRegions, .skinExcluded, .garmentRegions],
                                      maskCoverage: 0.18)
        let record = ScanRecord.make(from: result(), source: .camera, assetLocalId: "asset-2", subject: subject,
                                     garments: garments(), policyVersion: AnalysisPolicy.current)
        try await scans.insert(record)
        let stored = try await scans.fetch(id: record.id)
        let back = try XCTUnwrap(stored)
        XCTAssertEqual(back.garmentRegions, 2)
        XCTAssertEqual(back.enginePolicyVersion, AnalysisPolicy.current)
        XCTAssertFalse(back.needsReanalysis)
        let pendingCount = try await scans.needingReanalysis().count
        XCTAssertEqual(pendingCount, 0)
        let colors = back.garmentColors
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(colors.map(\.hex), ["#ddc0c8", "#2b2c2c"])
        XCTAssertEqual(colors.map(\.region), [2, 1])
        XCTAssertEqual(colors.map(\.regionLabel), ["Parte de abajo", "Parte de arriba"])
        XCTAssertEqual(colors.map(\.mergedClusters), [4, 2])
        XCTAssertEqual(colors[0].regionShare, 0.45)
        XCTAssertEqual(colors[0].weight, 0.6)
        XCTAssertEqual(back.maskStepValues, [.poseRegions, .skinExcluded, .garmentRegions])
        // Sin prendas (camino clásico, sin pose): columnas nil y re-análisis pendiente si no hay versión.
        let classic = ScanRecord.make(from: result(), source: .picker, subject: subject)
        XCTAssertNil(classic.garmentsJson)
        XCTAssertNil(classic.garmentRegions)
        XCTAssertNil(classic.enginePolicyVersion)
        XCTAssertTrue(classic.needsReanalysis)
        // Un scan clásico de esta política (sin pose) no se re-analiza en bucle.
        let classicTagged = ScanRecord.make(from: result(), source: .picker, subject: subject,
                                            policyVersion: AnalysisPolicy.current)
        XCTAssertFalse(classicTagged.needsReanalysis)
    }

    func testNeedsReanalysisRules() throws {
        var scan = ScanRecord.make(from: result(), source: .camera, policyVersion: AnalysisPolicy.current)
        XCTAssertFalse(scan.needsReanalysis)
        XCTAssertTrue(AnalysisPolicy.needsReanalysis(scan, policyVersion: AnalysisPolicy.current + 1),
                      "política nueva: re-analizar")
        XCTAssertTrue(AnalysisPolicy.needsReanalysis(scan, engineVersion: "9.9.9"), "motor nuevo: re-analizar")
        XCTAssertTrue(AnalysisPolicy.needsReanalysis(scan, dictVersion: "otro"), "diccionario nuevo: re-analizar")
        scan.enginePolicyVersion = nil
        XCTAssertTrue(scan.needsReanalysis, "scan anterior a v4: re-analizar")
        // Un desbloqueo manual no tiene foto que volver a analizar.
        let manual = ScanRecord.make(from: result(), source: .manual)
        XCTAssertFalse(manual.needsReanalysis)
    }
}
