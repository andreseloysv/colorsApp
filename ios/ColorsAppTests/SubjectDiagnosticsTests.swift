// Diagnóstico con recorte de sujeto: al votar se guardan, junto al PNG de 256 px,
// las máscaras de las variantes largest / largest-clothing / largest-clothing-skin
// (PGM del tamaño exacto del PNG), el JSON del recorte, el label map y
// debug.json; el zip las incluye como images/<scan_id>.<sufijo> y feedback.csv /
// scans.csv llevan las columnas del recorte.
import XCTest
import ImageIO
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class SubjectDiagnosticsTests: XCTestCase {
    func testVoteStoresMasksAndExportIncludesThem() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-subjdiag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let scene = SyntheticPersonScene.make()
        let timing = TimingLog(url: dir.appendingPathComponent("times.txt"))
        let outcome = try await ScanAnalyzer.run(image: try XCTUnwrap(scene.image), source: .picker, subject: .default,
                                                 people: [scene.person], env: env, timing: timing,
                                                 now: Date(timeIntervalSince1970: 1_760_000_000))
        let store = FeedbackImageStore(directory: dir.appendingPathComponent("images", isDirectory: true))
        let model = ResultViewModel(outcome: outcome, env: env, imageStore: store, timing: timing)
        await model.load()
        await model.vote(.no)
        await model.feedbackImageTask?.value

        let id = outcome.scan.id
        let attachment = try XCTUnwrap(store.attachment(scanId: id))
        XCTAssertEqual(attachment.extras.map(\.suffix),
                       ["debug.json", "json", "labels.png", "largest-clothing-skin.pgm", "largest-clothing.pgm", "largest.pgm"])
        let pngSource = try XCTUnwrap(CGImageSourceCreateWithData(attachment.png as CFData, nil))
        let png = try XCTUnwrap(CGImageSourceCreateImageAtIndex(pngSource, 0, nil))
        XCTAssertEqual(png.width, 192)
        XCTAssertEqual(png.height, 256)
        var coverages: [String: Double] = [:]
        for extra in attachment.extras where extra.suffix.hasSuffix(".pgm") {
            let parsed = try XCTUnwrap(PNM.read(extra.data), extra.suffix)
            XCTAssertEqual(parsed.width, png.width, "\(extra.suffix) mide lo mismo que el PNG")
            XCTAssertEqual(parsed.height, png.height)
            XCTAssertEqual(parsed.channels, 1)
            coverages[extra.suffix] = MaskOps.coverage(parsed.bytes, width: parsed.width, height: parsed.height)
        }
        let whole = try XCTUnwrap(coverages["largest.pgm"])
        let clothing = try XCTUnwrap(coverages["largest-clothing.pgm"])
        let skin = try XCTUnwrap(coverages["largest-clothing-skin.pgm"])
        XCTAssertGreaterThan(whole, clothing, "solo ropa quita cabeza, antebrazos y manos")
        XCTAssertGreaterThan(clothing, skin, "la piel quita escote y cuello")
        // La variante de la app (largest-clothing-skin) es la máscara del análisis reescalada.
        let expected = try LayerBitmaps.resample(mask: try XCTUnwrap(outcome.subject.mask), width: outcome.raster.width,
                                                 height: outcome.raster.height, toWidth: png.width, toHeight: png.height)
        let appVariant = try XCTUnwrap(attachment.extras.first { $0.suffix == "largest-clothing-skin.pgm" })
        XCTAssertEqual(PNM.read(appVariant.data)?.bytes, expected)

        let subjectJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(attachment.extras.first { $0.suffix == "json" }).data) as? [String: Any])
        XCTAssertEqual(subjectJSON["scan_id"] as? String, id)
        XCTAssertEqual(subjectJSON["vision"] as? String, "run")
        XCTAssertEqual(subjectJSON["origin"] as? String, "analysis")
        let subject = try XCTUnwrap(subjectJSON["subject"] as? [String: Any])
        XCTAssertEqual(subject["steps"] as? [String], ["poseRegions", "skinExcluded"])
        XCTAssertEqual(subject["people_count"] as? Int, 1)
        XCTAssertEqual((subjectJSON["people"] as? [[String: Any]])?.count, 1)
        let variants = try XCTUnwrap(subjectJSON["variants"] as? [String: Any])
        XCTAssertEqual(((variants["largest-clothing"] as? [String: Any])?["file"] as? String), "\(id).largest-clothing.pgm")
        XCTAssertNotNil((subjectJSON["timings_ms"] as? [String: Any])?["engine"])
        let debugJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(attachment.extras.first { $0.suffix == "debug.json" }).data) as? [String: Any])
        XCTAssertEqual((debugJSON["explain"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((debugJSON["hits"] as? [[String: Any]])?.first?["id"] as? Int, outcome.result.hits.first?.comboId)

        // Zip: PNG + extras por scan y columnas del recorte.
        let provider: Diagnostics.PhotoProvider = { scan in store.attachment(scanId: scan.id) }
        let export = try await Diagnostics.export(scans: env.scans, feedback: env.feedback, timings: timing,
                                                  photoProvider: provider, directory: dir, now: Date(timeIntervalSince1970: 1_760_000_100))
        XCTAssertEqual(export.images, 1)
        let entries = try Zip.entries(in: Data(contentsOf: export.url))
        let names = entries.map(\.name)
        for suffix in ["png", "largest.pgm", "largest-clothing.pgm", "largest-clothing-skin.pgm", "json", "labels.png", "debug.json"] {
            XCTAssertTrue(names.contains("images/\(id).\(suffix)"), "falta images/\(id).\(suffix) en \(names)")
        }
        let feedbackCSV = try XCTUnwrap(entries.first { $0.name == "feedback.csv" }).text
        let lines = feedbackCSV.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, Diagnostics.feedbackHeader)
        XCTAssertTrue(lines[1].hasSuffix(",largestPerson,clothing,1,1,0"), lines[1])
        let scansCSV = try XCTUnwrap(entries.first { $0.name == "scans.csv" }).text
        XCTAssertTrue(scansCSV.hasPrefix(Diagnostics.scansHeader + "\n"))
        XCTAssertTrue(scansCSV.contains(",largestPerson,clothing,1,1,0,\"[\"\"poseRegions\"\",\"\"skinExcluded\"\"]\","), scansCSV)
        let readme = try XCTUnwrap(entries.first).text
        XCTAssertTrue(readme.contains("largest-clothing-skin"))
        let times = try XCTUnwrap(entries.first { $0.name == "times.txt" }).text
        XCTAssertTrue(times.contains("analyze.picker.vision"))
    }

    func testNoPeopleWritesNoMasks() throws {
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        let analysis = try ScanAnalyzer.analyze(image: image, subject: .default, people: [])
        XCTAssertEqual(analysis.subject.steps, [.noPeople])
        let extras = try DiagnosticsSubject.extras(.init(scanId: "s", analysis: analysis, origin: "analysis"))
        XCTAssertEqual(extras.map(\.suffix), ["debug.json", "json", "labels.png"], "sin personas: sin PGM (el motor usa la foto completa)")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(extras.first { $0.suffix == "json" }).data) as? [String: Any])
        let variants = try XCTUnwrap(json["variants"] as? [String: [String: Any]])
        XCTAssertTrue(variants["largest"]?["file"] is NSNull)
        XCTAssertEqual(variants["largest"]?["steps"] as? [String], ["noPeople"])
    }
}
