// Diagnóstico: zip propio (ida y vuelta, deflate/stored, CRC), exportación con
// feedback.csv de una fila, notas de fotos omitidas, versión de GRDB cruzada
// con Package.resolved, escapado CSV y TimingLog.
import XCTest
import ColorEngine
import SubjectKit
@testable import ColorsApp

final class DiagnosticsTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-diag-\(UUID().uuidString)", isDirectory: true)
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

    func testZipRoundTripStoredAndDeflated() throws {
        let text = String(repeating: "scan_id,verdict,top1\n", count: 200)
        var noise = [UInt8](repeating: 0, count: 3000)
        var state: UInt32 = 12345
        for i in noise.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            noise[i] = UInt8(state >> 24)
        }
        let entries = [
            ZipEntry(name: "feedback.csv", text: text),
            ZipEntry(name: "images/ruido.bin", data: Data(noise)),
            ZipEntry(name: "vacío.txt", data: Data()),
        ]
        let archive = Zip.archive(entries, date: Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual([UInt8](archive.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertLessThan(archive.count, text.utf8.count + noise.count, "el texto repetido debe comprimir")
        let back = try Zip.entries(in: archive)
        XCTAssertEqual(back, entries)
        XCTAssertEqual(back[0].text, text)
        // Sin compresión (todo stored) también es válido.
        let stored = Zip.archive(entries, compress: false)
        XCTAssertEqual(try Zip.entries(in: stored), entries)
        XCTAssertGreaterThan(stored.count, archive.count)
        // CRC-32 de referencia: "123456789" -> 0xCBF43926.
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(Zip.crc32(Data()), 0)
        XCTAssertThrowsError(try Zip.entries(in: Data("no es un zip".utf8)))
        // Un byte corrupto en el contenido rompe el CRC.
        var corrupt = stored
        let payloadOffset = 30 + "feedback.csv".utf8.count + 5
        corrupt[payloadOffset] ^= 0xFF
        XCTAssertThrowsError(try Zip.entries(in: corrupt)) { error in
            XCTAssertEqual(error as? ZipError, .badCRC("feedback.csv"))
        }
    }

    func testExportContainsFeedbackCSVWithOneRow() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase.inMemory()
        let scans = ScanRepository(db)
        let feedback = FeedbackRepository(db)
        let scannedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let votedAt = Date(timeIntervalSince1970: 1_750_000_060)
        let scan = ScanRecord.make(from: sampleResult(), source: .picker, assetLocalId: "asset-secreto", now: scannedAt)
        try await scans.insert(scan)
        try await feedback.record(scanId: scan.id, verdict: .yes, at: votedAt)
        let timing = TimingLog(url: dir.appendingPathComponent("times.txt"))
        timing.record("analyze.picker", ms: 42, now: votedAt)
        timing.record("scan.done", ms: 1234, now: votedAt)

        let pngImage = try XCTUnwrap(SyntheticImage.blocks(colors: [SyntheticImage.RGB(r: 10, g: 20, b: 30)], size: 8, grid: 1))
        let png = try XCTUnwrap(PNGCoding.png(from: pngImage))
        let provider: Diagnostics.ImageProvider = { _ in png }

        let export = try await Diagnostics.export(scans: scans, feedback: feedback, timings: timing,
                                                  imageProvider: provider, directory: dir, now: votedAt)
        XCTAssertEqual(export.feedbackRows, 1)
        XCTAssertEqual(export.scanRows, 1)
        XCTAssertEqual(export.images, 1)
        XCTAssertEqual(export.omittedImages, 0)
        XCTAssertEqual(export.url.pathExtension, "zip")
        XCTAssertTrue(export.url.lastPathComponent.hasPrefix("colorsapp-diagnostico-"))

        let entries = try Zip.entries(in: Data(contentsOf: export.url))
        XCTAssertEqual(entries.map(\.name), ["README.txt", "feedback.csv", "scans.csv", "times.txt", "images/\(scan.id).png"])

        let csv = try XCTUnwrap(entries.first { $0.name == "feedback.csv" }).text
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2, csv)
        XCTAssertEqual(lines[0], "scan_id,verdict,top1,top2,top3,scores,created_at,subject_mode,region_mode,adaptive_skin,people_count,person_index")
        let row = lines[1]
        XCTAssertTrue(row.hasPrefix("\(scan.id),yes,3,102,31,"), row)
        XCTAssertTrue(row.contains("\"[1e-12,11.418745355239,17.94]\""), "scores entrecomillado: \(row)")
        XCTAssertTrue(row.hasSuffix(",\(Diagnostics.iso(votedAt)),,,,,"), "scan sin datos de recorte: columnas vacías: \(row)")

        let scansCSV = try XCTUnwrap(entries.first { $0.name == "scans.csv" }).text
        XCTAssertEqual(scansCSV.split(separator: "\n").count, 2)
        XCTAssertTrue(scansCSV.hasPrefix(Diagnostics.scansHeader + "\n"))
        XCTAssertFalse(scansCSV.contains("asset-secreto"), "scans.csv no lleva identificadores de fotos")
        XCTAssertTrue(scansCSV.contains("#ffefae:0.5600;#bb7125:0.4400"))

        let times = try XCTUnwrap(entries.first { $0.name == "times.txt" }).text
        XCTAssertTrue(times.contains("analyze.picker 42 ms"))
        XCTAssertTrue(times.contains("scan.done 1234 ms"))

        let image = try XCTUnwrap(entries.last)
        XCTAssertEqual(image.data, png)
        let readme = try XCTUnwrap(entries.first).text
        XCTAssertTrue(readme.contains("GRDB \(Diagnostics.grdbVersion)"))
        // Ruta impresa para verificar el zip desde el Mac (unzip -t).
        print("DiagnosticsTests zip: \(export.url.path)")
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-diagnostico-last.zip")
        try? FileManager.default.removeItem(at: keep)
        try FileManager.default.copyItem(at: export.url, to: keep)
        print("DiagnosticsTests zip copy: \(keep.path)")
    }

    func testExportWithoutImagesNotesOmission() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase.inMemory()
        let scans = ScanRepository(db)
        let feedback = FeedbackRepository(db)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let scan = ScanRecord.make(from: sampleResult(), source: .camera, now: now)
        try await scans.insert(scan)
        try await feedback.record(scanId: scan.id, verdict: .no, at: now)
        try await feedback.record(scanId: scan.id, verdict: .yes, at: now.addingTimeInterval(1))
        let export = try await Diagnostics.export(scans: scans, feedback: feedback,
                                                  timings: TimingLog(url: dir.appendingPathComponent("t.txt")),
                                                  imageProvider: nil, directory: dir, now: now)
        XCTAssertEqual(export.feedbackRows, 2)
        XCTAssertEqual(export.images, 0)
        XCTAssertEqual(export.omittedImages, 1, "una foto (un scan) omitida aunque tenga dos veredictos")
        XCTAssertEqual(export.notes.count, 1)
        XCTAssertTrue(export.notes[0].contains("omitidas"))
        let entries = try Zip.entries(in: Data(contentsOf: export.url))
        XCTAssertEqual(entries.map(\.name), ["README.txt", "feedback.csv", "scans.csv", "times.txt"])
        let csv = try XCTUnwrap(entries.first { $0.name == "feedback.csv" }).text
        XCTAssertEqual(csv.split(separator: "\n").count, 3)
        XCTAssertEqual(try XCTUnwrap(entries.first { $0.name == "times.txt" }).data.count, 0)
    }

    func testGRDBVersionMatchesPackageResolved() throws {
        // #filePath: ios/ColorsAppTests/DiagnosticsTests.swift -> ios/ColorsApp.xcodeproj/.../Package.resolved
        let iosDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let resolved = iosDir.appendingPathComponent("ColorsApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        guard let data = try? Data(contentsOf: resolved) else {
            throw XCTSkip("Package.resolved no accesible desde el simulador: \(resolved.path)")
        }
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable { let version: String? }
                let identity: String
                let state: State
            }
            let pins: [Pin]
        }
        let pins = try JSONDecoder().decode(Resolved.self, from: data).pins
        let grdb = try XCTUnwrap(pins.first { $0.identity == "grdb.swift" })
        XCTAssertEqual(grdb.state.version, Diagnostics.grdbVersion)
        XCTAssertTrue(Diagnostics.sqliteVersion.hasPrefix("3."))
    }

    func testCSVEscaping() {
        XCTAssertEqual(Diagnostics.csvField("simple"), "simple")
        XCTAssertEqual(Diagnostics.csvField("a,b"), "\"a,b\"")
        XCTAssertEqual(Diagnostics.csvField("di\"jo"), "\"di\"\"jo\"")
        XCTAssertEqual(Diagnostics.csvField("dos\nlíneas"), "\"dos\nlíneas\"")
        let csv = Diagnostics.feedbackCSV([], scans: [:])
        XCTAssertEqual(csv, Diagnostics.feedbackHeader + "\n")
    }

    func testTimingLogAppendsAndClears() {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = TimingLog(url: dir.appendingPathComponent("sub/times.txt"))
        XCTAssertEqual(log.text(), "")
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        log.record("analyze.camera", ms: 7, now: t)
        log.record("scan.done", ms: 90_000, now: t)
        let lines = log.text().split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(lines[0]), "\(Diagnostics.iso(t)) analyze.camera 7 ms")
        XCTAssertEqual(String(lines[1]), "\(Diagnostics.iso(t)) scan.done 90000 ms")
        log.clear()
        XCTAssertEqual(log.text(), "")
    }

    /// Sustituye a testPersonMaskHelpers (PersonMask de F6 se retiró: la máscara la
    /// calcula SubjectKit): cobertura de SubjectKit y remuestreo de máscaras al PNG de 256 px.
    func testPersonMaskHelpers() throws {
        XCTAssertEqual(MaskOps.coverage([0, 0, 255, 128], width: 2, height: 2), 0.5)
        XCTAssertEqual(MaskOps.coverage([0, 0, 0, 127], width: 2, height: 2), 0)
        let mask = [UInt8](repeating: 255, count: 40 * 30)
        let small = try LayerBitmaps.resample(mask: mask, width: 40, height: 30, toWidth: 20, toHeight: 15)
        XCTAssertEqual(small.count, 20 * 15)
        XCTAssertTrue(small.allSatisfy { $0 == 255 })
        XCTAssertEqual(DiagnosticsSubject.exportSize(width: 1024, height: 682).width, 256)
        XCTAssertEqual(DiagnosticsSubject.exportSize(width: 300, height: 400).height, 256)
    }
}
