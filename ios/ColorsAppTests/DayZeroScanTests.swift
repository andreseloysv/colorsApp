// Escaneo del día 0 (PLAN §8 F7) en el simulador: `make ios-test-sim` concede
// el acceso a Fotos (`simctl privacy grant photos`) y añade al carrete los 20 PNG
// de Fixtures/sim_media (`simctl addmedia`, bandas con los colores exactos de 20
// combinaciones; `oracle/tools/make_sim_media.py`). Aquí `PhotoKitScanRunner`
// escanea las últimas 200 fotos sobre una base de datos en memoria y se exige:
// termina, procesa >= 20, `unlocks` > 0 y, para cada fixture, el top-1 del motor
// en el iPhone coincide con el de `ce match` (expected_sim_media.json).
//
// Emparejamiento scan <-> fixture: no por orden de creación (simctl addmedia da
// a todas la misma fecha) sino por la paleta guardada en el scan: una fixture
// casa con un scan si tiene el mismo número de swatches y cada color de la
// combinación está a ΔE00 <= 3 de algún swatch (`palette_match_max_de00`);
// entre varias candidatas gana la de menor ΔE00 máximo. La biblioteca de
// ejemplo del simulador (paisajes) también se escanea y no casa con ninguna.
import XCTest
import Combine
import Photos
import ImageIO
import SwiftUI
import UIKit
import ColorEngine
import SubjectKit
@testable import ColorsApp

final class DayZeroScanTests: XCTestCase {
    struct Expected: Decodable {
        struct ColorEntry: Decodable {
            let index: Int
            let name: String
            let hex: String
            let rgb: [Int]
        }

        struct HitEntry: Decodable {
            let id: Int
            let score: Double
        }

        struct Result: Decodable {
            let hits: [HitEntry]
            let ambiguous: Int
        }

        struct Entry: Decodable {
            let file: String
            let comboId: Int
            let size: Int
            let colors: [ColorEntry]
            let meanRgb: [Int]
            let expected: Result

            enum CodingKeys: String, CodingKey {
                case file, size, colors, expected
                case comboId = "combo_id"
                case meanRgb = "mean_rgb"
            }
        }

        let ceVersion: String
        let dictVersion: String
        let paletteMatchMaxDe00: Double
        let n: Int
        let entries: [Entry]

        enum CodingKeys: String, CodingKey {
            case n, entries
            case ceVersion = "ce_version"
            case dictVersion = "dict_version"
            case paletteMatchMaxDe00 = "palette_match_max_de00"
        }
    }

    /// Valores de `scanProgress` recibidos por Combine (clase para mutarla desde el sink).
    @MainActor
    private final class ProgressLog {
        var values: [ScanProgress] = []
    }

    private var bundle: Bundle { Bundle(for: DayZeroScanTests.self) }

    private func loadExpected() throws -> Expected {
        let url = try XCTUnwrap(bundle.url(forResource: "expected_sim_media", withExtension: "json"),
                                "expected_sim_media.json en el bundle de tests")
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url))
        XCTAssertEqual(expected.ceVersion, colorEngineVersion)
        XCTAssertEqual(expected.dictVersion, dictionaryVersion)
        XCTAssertEqual(expected.n, 20)
        XCTAssertEqual(expected.entries.count, 20)
        return expected
    }

    private func loadFixtureImage(_ name: String) throws -> CGImage {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let url = try XCTUnwrap(bundle.url(forResource: parts[0], withExtension: parts[1]), "\(name) en el bundle")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// ΔE00 máximo entre cada color de la fixture y su swatch más cercano del scan;
    /// nil si el número de swatches no coincide.
    private func paletteDistance(_ scan: ScanRecord, _ fixture: Expected.Entry) -> Double? {
        let swatches = scan.palette
        guard swatches.count == fixture.colors.count, !swatches.isEmpty else { return nil }
        var worst = 0.0
        for color in fixture.colors {
            let lab = srgbToLab(r: UInt8(color.rgb[0]), g: UInt8(color.rgb[1]), b: UInt8(color.rgb[2]))
            let best = swatches.map { deltaE2000(lab, Lab(L: $0.lab[0], a: $0.lab[1], b: $0.lab[2])) }.min() ?? .infinity
            worst = max(worst, best)
        }
        return worst
    }

    /// Fixture que mejor casa con el scan (ΔE00 máximo <= tolerancia), o nil.
    private func matchFixture(_ scan: ScanRecord, in expected: Expected) -> (Expected.Entry, Double)? {
        var best: (Expected.Entry, Double)?
        for entry in expected.entries {
            if let d = paletteDistance(scan, entry), d <= expected.paletteMatchMaxDe00, d < (best?.1 ?? .infinity) {
                best = (entry, d)
            }
        }
        return best
    }

    // MARK: Escaneo real del carrete del simulador

    @MainActor
    func testInitialScanOfSimulatorLibraryMatchesCLI() async throws {
        let expected = try loadExpected()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        XCTAssertEqual(status, .authorized,
                       "Fotos no está autorizado (\(status.rawValue)): ejecutar con `make ios-test-sim`, que hace `xcrun simctl privacy <udid> grant photos com.andreseloy.colorsapp` y `addmedia` antes del test")
        let assetsInLibrary = PhotoKitScanRunner.fetchLatestImageAssets(limit: 200).count
        XCTAssertGreaterThanOrEqual(assetsInLibrary, 20,
                                    "el carrete del simulador tiene \(assetsInLibrary) imágenes: faltan las fixtures (make ios-test-sim-media)")

        let env = try AppEnvironment.forTesting()
        let runner = env.installPhotoKitScanRunner()
        XCTAssertTrue(env.scanRunner === runner)
        XCTAssertTrue(env.installPhotoKitScanRunner() === runner, "instalar dos veces reutiliza el runner")
        // Progreso publicado por AppEnvironment (scanProgress) a través de onProgress.
        let log = ProgressLog()
        let subscription = env.$scanProgress.sink { log.values.append($0) }
        defer { subscription.cancel() }
        let t0 = Date()
        let summary = try await env.runInitialScan(limit: 200)
        let wallMs = Date().timeIntervalSince(t0) * 1000

        // Termina, procesa >= 20 y desbloquea algo.
        XCTAssertFalse(summary.needsPicker)
        XCTAssertGreaterThanOrEqual(summary.scanned, 20, "scanned \(summary.scanned)")
        XCTAssertEqual(summary.scanned + summary.skipped + summary.failed, min(200, assetsInLibrary))
        XCTAssertEqual(summary.failed, 0)
        XCTAssertGreaterThan(summary.newUnlocks.count, 0)
        XCTAssertEqual(summary.totalUnlocked, summary.newUnlocks.count, "base de datos nueva: todos los unlocks son nuevos")
        let unlockCount = try await env.unlocks.count()
        XCTAssertEqual(unlockCount, summary.totalUnlocked)
        XCTAssertEqual(Set(summary.newUnlocks).count, summary.newUnlocks.count, "sin repetidos")
        XCTAssertEqual(runner.progress.phase, .finished)
        XCTAssertEqual(runner.progress.processed, runner.progress.total)
        XCTAssertEqual(runner.progress.total, min(200, assetsInLibrary))
        XCTAssertEqual(runner.progress.unlocked, summary.newUnlocks.count)
        XCTAssertEqual(runner.progress.skipped, summary.skipped)
        XCTAssertGreaterThan(summary.duration, 0)
        XCTAssertEqual(runner.lastSummary, summary)
        XCTAssertEqual(runner.lastDurationMs, summary.duration * 1000, accuracy: 1)
        // Progreso observable: fases en orden y processed creciente.
        let progressLog = log.values.drop { $0.phase == .idle }
        XCTAssertEqual(progressLog.first?.phase, .requestingAccess)
        XCTAssertEqual(env.scanProgress, runner.progress)
        XCTAssertTrue(progressLog.contains { $0.phase == .fetching })
        let analyzing = progressLog.filter { $0.phase == .analyzing }.map(\.processed)
        XCTAssertEqual(analyzing, analyzing.sorted())
        XCTAssertEqual(analyzing.last, min(200, assetsInLibrary))
        XCTAssertEqual(progressLog.last?.phase, .finished)
        XCTAssertNotNil(progressLog.last?.startedAt)
        // Settings del escaneo.
        let done = try await env.settings.bool(.initialScanDone)
        XCTAssertTrue(done)
        let count = try await env.settings.int(.initialScanCount)
        XCTAssertEqual(count, summary.scanned)
        let at = try await env.settings.get(.initialScanAt)
        XCTAssertNotNil(at.flatMap { ISO8601DateFormatter().date(from: $0) })

        // Scans guardados: uno por foto analizada, source .library y asset_local_id real.
        let scans = try await env.scans.recent(limit: 400)
        XCTAssertEqual(scans.count, summary.scanned)
        XCTAssertTrue(scans.allSatisfy { $0.source == .library && $0.assetLocalId != nil && $0.top1 != nil })
        XCTAssertTrue(scans.allSatisfy { $0.engineVersion == colorEngineVersion && $0.dictVersion == dictionaryVersion })
        let localIds = Set(PhotoKitScanRunner.fetchLatestImageAssets(limit: 200).map(\.localIdentifier))
        XCTAssertTrue(scans.allSatisfy { localIds.contains($0.assetLocalId ?? "") }, "asset_local_id de PhotoKit")

        // Emparejamiento por paleta: cada fixture aparece y su top-1 es el del CLI.
        var matchedFixtures: [Int: Int] = [:]
        var report: [String] = []
        var unmatched = 0
        for scan in scans {
            guard let (fixture, distance) = matchFixture(scan, in: expected) else {
                unmatched += 1
                continue
            }
            matchedFixtures[fixture.comboId, default: 0] += 1
            XCTAssertEqual(scan.top1, fixture.expected.hits[0].id,
                           "\(fixture.file): top-1 en iPhone \(scan.top1 ?? -1) != CLI \(fixture.expected.hits[0].id) (ΔE00 paleta \(String(format: "%.3f", distance)))")
            XCTAssertEqual(scan.ambiguous, fixture.expected.ambiguous != 0, "\(fixture.file): ambiguous")
            XCTAssertEqual(scan.topIds.count, 3, "\(fixture.file): top-3 guardado")
            if scan.top1 == fixture.expected.hits[0].id, !scan.ambiguous {
                let unlocked = try await env.unlocks.isUnlocked(comboId: fixture.comboId)
                XCTAssertTrue(unlocked, "\(fixture.file): la combinación \(fixture.comboId) debería estar desbloqueada")
            }
            report.append(String(format: "%@: top-3 %@ (CLI %@), score1 %.3g, ΔE00 paleta máx %.3f, swatches %d",
                                 fixture.file, scan.topIds.map(String.init).joined(separator: ","),
                                 fixture.expected.hits.map { String($0.id) }.joined(separator: ","),
                                 scan.scoreValues.first ?? -1, distance, scan.palette.count))
        }
        for entry in expected.entries {
            XCTAssertNotNil(matchedFixtures[entry.comboId], "\(entry.file) no aparece en ningún scan (¿addmedia hecho?)")
        }
        XCTAssertEqual(matchedFixtures.count, 20)
        for entry in expected.entries where entry.expected.ambiguous == 0 {
            XCTAssertTrue(summary.newUnlocks.contains(entry.comboId), "\(entry.file): combo \(entry.comboId) no está en newUnlocks")
        }
        // Resumen: combinaciones y colores más frecuentes, color firma.
        XCTAssertFalse(summary.topCombos.isEmpty)
        XCTAssertEqual(summary.topCombos.map(\.count), summary.topCombos.map(\.count).sorted(by: >))
        XCTAssertEqual(summary.topCombos.reduce(0) { $0 + $1.count }, summary.scanned)
        XCTAssertFalse(summary.topColors.isEmpty)
        XCTAssertEqual(summary.signatureColorIndex, summary.topColors.first?.colorIndex)
        XCTAssertEqual(summary.topColors.map(\.count), summary.topColors.map(\.count).sorted(by: >))

        let timing = String(format: "scan.done %d %.0fms (wall %.0fms; %.1f ms/foto; omitidas %d; assets en carrete %d; unlocks nuevos %d; sin fixture %d; fallback highQualityFormat %d)",
                            summary.scanned, summary.duration * 1000, wallMs,
                            summary.duration * 1000 / Double(max(1, summary.scanned)),
                            summary.skipped, assetsInLibrary, summary.newUnlocks.count, unmatched, runner.lastFallbacks)
        print("DayZeroScanTests: " + timing)
        print(report.joined(separator: "\n"))
        let attachment = XCTAttachment(string: timing + "\n" + report.joined(separator: "\n"))
        attachment.name = "day-zero-scan-report"
        add(attachment)

        // Capturas (harness/out/screens-c): rejilla con los desbloqueos del escaneo y resumen Wrapped.
        try await captureScreens(env: env, summary: summary)
    }

    // MARK: Misma ruta con imágenes ya decodificadas (la del PhotosPicker en acceso limitado)

    @MainActor
    func testScanImagesRouteMatchesCLIWithoutPhotoKit() async throws {
        let expected = try loadExpected()
        let env = try AppEnvironment.forTesting()
        let runner = PhotoKitScanRunner(environment: env)
        env.setScanRunner(runner)
        var images: [(id: String?, image: CGImage)] = []
        for entry in expected.entries {
            images.append((id: "fixture:\(entry.file)", image: try loadFixtureImage(entry.file)))
        }
        // La misma PNG como bytes: la ruta de PhotosPicker (miniatura ImageIO <= 256 px).
        let firstURL = try XCTUnwrap(bundle.url(forResource: "sim_c003", withExtension: "png"))
        let thumb = try XCTUnwrap(PhotoKitScanRunner.decodeThumbnail(Data(contentsOf: firstURL), side: 256))
        XCTAssertEqual(thumb.width, 256)
        XCTAssertEqual(thumb.height, 256)
        let dataSummary = try await runner.scan(inputs: [.data(try Data(contentsOf: firstURL), id: "data:sim_c003")], startedAt: Date())
        XCTAssertEqual(dataSummary.scanned, 1)
        XCTAssertEqual(dataSummary.newUnlocks, [3])
        // Bytes ilegibles: omitida, sin fallo.
        let junk = try await runner.scan(inputs: [.data(Data([1, 2, 3]), id: "junk")], startedAt: Date())
        XCTAssertEqual(junk.scanned, 0)
        XCTAssertEqual(junk.skipped, 1)
        XCTAssertEqual(junk.failed, 0)

        let summary = try await runner.scan(images: images)
        XCTAssertEqual(summary.scanned, 20)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(env.scanProgress.phase, .finished)
        XCTAssertEqual(env.scanProgress.processed, 20)
        let scans = try await env.scans.recent(limit: 100)
        XCTAssertEqual(scans.count, 21, "1 por la ruta de datos + 20 imágenes; los bytes ilegibles no generan scan")
        for entry in expected.entries {
            let scan = try XCTUnwrap(scans.first { $0.assetLocalId == "fixture:\(entry.file)" }, entry.file)
            XCTAssertEqual(scan.topIds, entry.expected.hits.map(\.id), "\(entry.file): top-3 == CLI")
            XCTAssertEqual(scan.ambiguous, entry.expected.ambiguous != 0)
            for (s, e) in zip(scan.scoreValues, entry.expected.hits) {
                XCTAssertEqual(s, e.score, accuracy: 1e-9, "\(entry.file): score combo \(e.id)")
            }
            let d = try XCTUnwrap(paletteDistance(scan, entry), "\(entry.file): mismo número de swatches")
            XCTAssertLessThan(d, 0.01, "\(entry.file): la paleta recupera los colores exactos")
        }
        // Todas son limpias y no ambiguas: 20 desbloqueos (el 3 ya estaba por la ruta de datos).
        XCTAssertEqual(Set(summary.newUnlocks), Set(expected.entries.map(\.comboId)).subtracting([3]))
        XCTAssertEqual(summary.totalUnlocked, 20)
        XCTAssertEqual(summary.topCombos.count, 20)
        XCTAssertTrue(summary.topCombos.allSatisfy { $0.count == 1 })
        XCTAssertEqual(summary.topCombos.map(\.comboId), summary.topCombos.map(\.comboId).sorted(), "empates por id ascendente")
        // Color firma: el color que más combinaciones de las 20 comparten.
        var counts: [Int: Int] = [:]
        for entry in expected.entries {
            for c in entry.colors { counts[c.index, default: 0] += 1 }
        }
        let bestCount = counts.values.max() ?? 0
        let signature = try XCTUnwrap(summary.signatureColorIndex)
        XCTAssertEqual(counts[signature], bestCount)
        XCTAssertEqual(signature, counts.filter { $0.value == bestCount }.keys.min())
        XCTAssertEqual(summary.topColors.reduce(0) { $0 + $1.count }, expected.entries.reduce(0) { $0 + $1.size })
    }

    // MARK: Regla de desbloqueo y acceso limitado

    func testStepsTextCountsRejectedPhantoms() {
        // Resumen del log del escaneo: las fotos sin nadie con una persona fantasma descartada
        // cuentan en rejectedPhantom y en noPeople (foto completa).
        let steps: [[MaskFallback]] = [[.rejectedPhantom, .noPeople], [.noPeople], [.poseRegions, .skinExcluded],
                                       [.rejectedPhantom, .noPeople]]
        var counts: [String: Int] = [:]
        for s in steps { for step in s { counts[step.rawValue, default: 0] += 1 } }
        XCTAssertEqual(PhotoKitScanRunner.stepsText(counts), "noPeople 3, poseRegions 1, rejectedPhantom 2, skinExcluded 1")
        XCTAssertEqual(MaskFallback(rawValue: "rejectedPhantom"), .rejectedPhantom)
    }

    func testUnlockRule() {
        let policy = ScanPolicy.default
        XCTAssertEqual(policy.unlockMaxScore, 12.0)
        XCTAssertEqual(policy.concurrency, 3)
        XCTAssertEqual(policy.targetSide, 256)
        func result(score: Double, ambiguous: Bool) -> AnalysisResult {
            AnalysisResult(swatches: [], hits: [Hit(comboId: 42, score: score), Hit(comboId: 7, score: score + 0.5)],
                           ambiguous: ambiguous, hash: 0)
        }
        XCTAssertEqual(policy.unlockCandidate(result(score: 0, ambiguous: false)), 42)
        XCTAssertEqual(policy.unlockCandidate(result(score: 12.0, ambiguous: false)), 42)
        XCTAssertNil(policy.unlockCandidate(result(score: 12.0001, ambiguous: false)), "por encima del umbral")
        XCTAssertNil(policy.unlockCandidate(result(score: 0, ambiguous: true)), "ambigua")
        XCTAssertNil(policy.unlockCandidate(AnalysisResult(swatches: [], hits: [], ambiguous: false, hash: 0)))
        var lax = policy
        lax.requireUnambiguous = false
        lax.unlockMaxScore = 20
        XCTAssertEqual(lax.unlockCandidate(result(score: 15, ambiguous: true)), 42)
    }

    @MainActor
    func testLimitedAccessSummaryAsksForPicker() async throws {
        let env = try AppEnvironment.forTesting()
        try await env.unlocks.unlock(comboId: 9, source: .manual)
        let summary = ScanSummary.empty(needsPicker: true, totalUnlocked: 1)
        XCTAssertTrue(summary.needsPicker)
        XCTAssertEqual(summary.scanned, 0)
        XCTAssertEqual(summary.totalUnlocked, 1)
        XCTAssertTrue(summary.newUnlocks.isEmpty)
        // La vista de escaneo y el Wrapped vacío se construyen sin crash.
        let wrapped = WrappedSummaryView(summary: summary, dictionary: env.dictionary, totalCombos: env.comboCount)
            .frame(width: 390, height: 600)
        XCTAssertNotNil(ImageRenderer(content: wrapped).cgImage)
        XCTAssertEqual(WrappedSummaryView.durationText(3.24), "3,2 s")
        XCTAssertEqual(WrappedSummaryView.durationText(72), "1 min 12 s")
    }

    // MARK: Capturas

    /// Renderiza la rejilla (con los desbloqueos del escaneo) y el resumen Wrapped
    /// dentro de la ventana de la app (drawHierarchy) y las guarda como PNG en
    /// `$COLORSAPP_SCREENS_DIR` (xcodebuild: TEST_RUNNER_COLORSAPP_SCREENS_DIR).
    @MainActor
    private func captureScreens(env: AppEnvironment, summary: ScanSummary) async throws {
        let model = RejillaModel()
        try await model.refresh(env.unlocks)
        XCTAssertEqual(model.unlockedCount, summary.totalUnlocked)
        let grid = NavigationStack {
            RejillaContentView(model: model, dictionary: env.dictionary)
                .navigationTitle("Rejilla")
        }
        let wrapped = NavigationStack {
            WrappedSummaryView(summary: summary, dictionary: env.dictionary, totalCombos: env.comboCount, onShowGrid: {})
        }
        let gridImage = try await snapshot(AnyView(grid))
        let wrappedImage = try await snapshot(AnyView(wrapped))
        XCTAssertGreaterThan(gridImage.size.width, 0)
        XCTAssertGreaterThan(wrappedImage.size.width, 0)
        for (name, image) in [("rejilla", gridImage), ("wrapped", wrappedImage)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            add(attachment)
        }
        guard let dir = ProcessInfo.processInfo.environment["COLORSAPP_SCREENS_DIR"], !dir.isEmpty else {
            print("DayZeroScanTests: COLORSAPP_SCREENS_DIR no definido; capturas solo como XCTAttachment")
            return
        }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (name, image) in [("rejilla", gridImage), ("wrapped", wrappedImage)] {
            let data = try XCTUnwrap(image.pngData())
            let url = base.appendingPathComponent("\(name).png")
            try data.write(to: url)
            print("DayZeroScanTests: captura \(url.path) (\(Int(image.size.width))x\(Int(image.size.height)) pt @\(Int(image.scale))x, \(data.count) bytes)")
        }
    }

    /// Muestra la vista en la ventana de la app hospedadora y la captura con
    /// drawHierarchy (captura real del simulador); si no hay ventana, ImageRenderer.
    @MainActor
    private func snapshot(_ view: AnyView) async throws -> UIImage {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first else {
            let renderer = ImageRenderer(content: view.frame(width: 390, height: 844).background(Color(.systemBackground)))
            renderer.scale = 2
            return try XCTUnwrap(renderer.uiImage)
        }
        let previous = window.rootViewController
        defer { window.rootViewController = previous }
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        host.view.layoutIfNeeded()
        // Dos vueltas del run loop para que LazyVGrid y la barra de navegación se asienten.
        try await Task.sleep(nanoseconds: 700_000_000)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
