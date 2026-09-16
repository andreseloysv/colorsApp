// Resultado sobre una imagen sintética de la combinación 12 (bloques con sus
// colores exactos): top-1 == 12, el flujo completo guarda el scan, el
// veredicto y el desbloqueo persisten en una AppDatabase en memoria, la
// tarjeta se renderiza a 1080 x 1350 px y el argumento -uiScreen se parsea.
import XCTest
import ImageIO
import UIKit
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class ResultViewModelTests: XCTestCase {
    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-result-\(UUID().uuidString)", isDirectory: true)
    }

    func testSyntheticCombo12AnalyzesToTopOne12() throws {
        let env = try makeEnvironment()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)

        let analysis = try ScanAnalyzer.analyze(image: image, subject: SubjectOptions(mode: .off))
        XCTAssertEqual(analysis.result.hits.map(\.comboId).first, 12)
        XCTAssertEqual(analysis.result.hits.count, 3)
        XCTAssertEqual(analysis.result.hits[0].score, 0, accuracy: 1e-9)
        XCTAssertFalse(analysis.result.ambiguous)
        XCTAssertFalse(analysis.maskApplied)
        XCTAssertEqual(analysis.subject.steps, [.none], "modo off: sin Vision ni máscara")
        // La paleta recupera los dos colores exactos de la combinación 12 (Isabella Color, Green Blue).
        XCTAssertEqual(Set(analysis.result.swatches.map(\.hex)), ["#c5a56e", "#099197"])
        XCTAssertEqual(analysis.result.swatches.map(\.weight).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(analysis.raster.width, 256)
        XCTAssertEqual(analysis.raster.height, 256)
        XCTAssertGreaterThanOrEqual(analysis.elapsedMs, 0)
    }

    func testRunPersistsScanAndVoteAndUnlockPersist() async throws {
        let env = try makeEnvironment()
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let timing = TimingLog(url: dir.appendingPathComponent("times.txt"))
        let past = Date(timeIntervalSince1970: 1_750_000_000)

        let outcome = try await ScanAnalyzer.run(image: image, source: .picker, assetLocalId: "asset-12",
                                                  subject: SubjectOptions(mode: .off), env: env, timing: timing, now: past)
        XCTAssertEqual(outcome.scan.top1, 12)
        XCTAssertEqual(outcome.scan.source, .picker)
        XCTAssertEqual(outcome.scan.assetLocalId, "asset-12")
        XCTAssertEqual(outcome.scan.engineVersion, colorEngineVersion)
        let storedOptional = try await env.scans.fetch(id: outcome.scan.id)
        let stored = try XCTUnwrap(storedOptional)
        XCTAssertEqual(stored.topIds.first, 12)
        XCTAssertEqual(stored.palette.count, 2)
        XCTAssertTrue(timing.text().contains("analyze.picker"))

        let store = FeedbackImageStore(directory: dir.appendingPathComponent("images", isDirectory: true))
        let model = ResultViewModel(outcome: outcome, env: env, imageStore: store)
        await model.load()
        XCTAssertNil(model.verdict)
        XCTAssertEqual(model.unlockState, .locked)
        // Título: nombre aceptado → propuesto (names.suggested.json) → «Nº 012».
        XCTAssertEqual(model.title, ComboNaming.bundled.name(for: 12, in: env.dictionary).text)
        XCTAssertNil(model.ambiguityText)
        XCTAssertEqual(model.otherHits.count, 2)

        // Veredicto: persiste y desactiva los botones (verdict != nil).
        await model.vote(.yes)
        XCTAssertEqual(model.verdict, .yes)
        XCTAssertNil(model.errorMessage)
        let latest = try await env.feedback.latest(forScan: outcome.scan.id)
        XCTAssertEqual(latest?.verdict, .yes)
        await model.vote(.no) // ya votado: no cambia
        XCTAssertEqual(model.verdict, .yes)
        let all = try await env.feedback.forScan(id: outcome.scan.id)
        XCTAssertEqual(all.count, 1)

        // Copia PNG sRGB de 256 px del raster (diagnóstico), escrita en segundo plano.
        var png: Data?
        for _ in 0..<50 {
            png = store.data(scanId: outcome.scan.id)
            if png != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let pngData = try XCTUnwrap(png, "copia PNG del feedback")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(pngData as CFData, nil))
        let copy = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(copy.width, 256)
        XCTAssertEqual(copy.height, 256)

        // Desbloqueo: nuevo la primera vez, con el origen y el scan del resultado.
        await model.unlock()
        XCTAssertEqual(model.unlockState, .unlockedNow)
        let unlocked = try await env.unlocks.isUnlocked(comboId: 12)
        XCTAssertTrue(unlocked)
        let records = try await env.unlocks.all()
        XCTAssertEqual(records.map(\.comboId), [12])
        XCTAssertEqual(records.first?.source, .picker)
        XCTAssertEqual(records.first?.scanId, outcome.scan.id)
        XCTAssertEqual(records.first?.assetLocalId, "asset-12")

        // Un segundo modelo sobre el mismo resultado ve el estado persistido: "ya en tu rejilla".
        let again = ResultViewModel(outcome: outcome, env: env, imageStore: store)
        await again.load()
        XCTAssertEqual(again.verdict, .yes)
        XCTAssertEqual(again.unlockState, .alreadyUnlocked)
        await again.unlock()
        XCTAssertEqual(again.unlockState, .alreadyUnlocked)
        let count = try await env.unlocks.count()
        XCTAssertEqual(count, 1)
    }

    func testAmbiguityTextAndHeadline() throws {
        let env = try makeEnvironment()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let raster = try EngineBridge.rasterize(image)
        let ambiguous = AnalysisResult(swatches: [], hits: [Hit(comboId: 12, score: 1.0), Hit(comboId: 178, score: 1.5)],
                                       ambiguous: true, hash: 0)
        let scan = ScanRecord.make(from: ambiguous, source: .camera, now: Date(timeIntervalSince1970: 1_750_000_000))
        let outcome = ScanOutcome(image: image, raster: raster, result: ambiguous, scan: scan)
        let model = ResultViewModel(outcome: outcome, env: env)
        XCTAssertEqual(model.ambiguityText, "Entre Nº 012 y Nº 178")
        XCTAssertEqual(model.shareTitle, "\(AppBrand.name) · Wada Nº 012")
        let combo = try XCTUnwrap(model.top1Combo)
        XCTAssertEqual(model.comboHeadline(combo), "2 colores")
    }

    func testShareCardRenders1080x1350() async throws {
        let env = try makeEnvironment()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let outcome = try await ScanAnalyzer.run(image: image, source: .manual, subject: SubjectOptions(mode: .off), env: env,
                                                  timing: TimingLog(url: temporaryDirectory().appendingPathComponent("t.txt")),
                                                  now: Date(timeIntervalSince1970: 1_750_000_001))
        let card = ShareCardRenderer.card(for: outcome, dictionary: env.dictionary)
        XCTAssertEqual(card.title, "Nº 012")
        XCTAssertEqual(card.number, "Nº 012")
        XCTAssertEqual(card.comboColors.count, 2)
        XCTAssertEqual(card.palette.count, 2)

        let rendered = try XCTUnwrap(ShareCardRenderer.render(card))
        let cg = try XCTUnwrap(rendered.cgImage)
        XCTAssertEqual(cg.width, 1080)
        XCTAssertEqual(cg.height, 1350)
        XCTAssertEqual(Double(cg.width) / Double(cg.height), 4.0 / 5.0, accuracy: 1e-9)
        XCTAssertEqual(rendered.size.width * rendered.scale, 1080, accuracy: 0.5)

        // No vacía: la imagen tiene más de un valor de píxel (foto, swatches y texto).
        let raster = try EngineBridge.rasterize(cg, maxSide: 4096)
        XCTAssertEqual(raster.width, 1080)
        var distinct = Set<UInt32>()
        for i in stride(from: 0, to: raster.pixels.count, by: 4 * 97) {
            let px = UInt32(raster.pixels[i]) << 16 | UInt32(raster.pixels[i + 1]) << 8 | UInt32(raster.pixels[i + 2])
            distinct.insert(px)
            if distinct.count > 8 { break }
        }
        XCTAssertGreaterThan(distinct.count, 3, "la tarjeta renderizada parece vacía")
        // Los colores de la combinación 12 aparecen en la tarjeta (swatches y franjas de la foto sintética).
        let hexes = Set(stride(from: 0, to: raster.pixels.count, by: 4).map {
            String(format: "#%02x%02x%02x", raster.pixels[$0], raster.pixels[$0 + 1], raster.pixels[$0 + 2])
        })
        XCTAssertTrue(hexes.contains("#c5a56e"))
        XCTAssertTrue(hexes.contains("#099197"))
    }

    func testDebugLaunchArgumentParsing() {
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "result-demo"]), .resultDemo)
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "explorar-12"]), .explorar(12))
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "explorar-348"]), .explorar(348))
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "ajustes"]), .ajustes)
        XCTAssertNil(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen"]))
        XCTAssertNil(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "otra"]))
        XCTAssertNil(DebugLaunch.screen(from: ["ColorsApp"]))
        XCTAssertEqual(DebugLaunch.demoComboId, 12)
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "layers-demo"]), .layersDemo)
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "layers-people"]), .layersPeople)
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "result-people"]), .resultPeople)
        XCTAssertEqual(DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", "result-people-mask"]), .resultPeopleMask)
        XCTAssertEqual(DebugLaunch.layer(from: ["ColorsApp", "-uiScreen", "layers-demo", "-uiLayer", "6"]), 6)
        XCTAssertNil(DebugLaunch.layer(from: ["ColorsApp", "-uiLayer", "12"]))
        XCTAssertNotNil(DebugLaunch.groupPhoto(), "la foto de grupo de depuración está en el bundle de Debug")
    }

    func testSyntheticImageCoversAllComboSizes() throws {
        let env = try makeEnvironment()
        for id in [1, 12, 200, 348] {
            let combo = try XCTUnwrap(env.dictionary.combo(id: id))
            let image = try XCTUnwrap(SyntheticImage.blocks(comboId: id, dictionary: env.dictionary))
            let palette = try EngineBridge.extractPalette(cgImage: image)
            XCTAssertEqual(palette.count, combo.size, "combo \(id)")
            XCTAssertEqual(Set(palette.map(\.hex)), Set(env.dictionary.colors(of: combo).map(\.hex)), "combo \(id)")
        }
        XCTAssertNil(SyntheticImage.blocks(comboId: 999, dictionary: env.dictionary))
    }

    func testImageLoadingAppliesOrientationAndLimitsSize() throws {
        // PNG 300 x 200 con orientación EXIF 6 (rotar 90° CW): debe llegar como 200 x 300.
        let env = try makeEnvironment()
        let wide = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary, size: 300))
        let cropped = try XCTUnwrap(wide.cropping(to: CGRect(x: 0, y: 0, width: 300, height: 200)))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cropped, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loaded = try ImageLoading.cgImage(from: data as Data)
        XCTAssertEqual(loaded.width, 200)
        XCTAssertEqual(loaded.height, 300)
        // Límite de tamaño: 300 px con máximo 100 -> lado mayor 100.
        let small = try ImageLoading.cgImage(from: data as Data, maxPixelSize: 100)
        XCTAssertEqual(max(small.width, small.height), 100)
        XCTAssertThrowsError(try ImageLoading.cgImage(from: Data([1, 2, 3])))
        // UIImage con orientación .right (cámara en vertical) -> CGImage vertical.
        let ui = UIImage(cgImage: cropped, scale: 1, orientation: .right)
        let upright = try XCTUnwrap(ImageLoading.upright(ui))
        XCTAssertEqual(upright.width, 200)
        XCTAssertEqual(upright.height, 300)
    }
}
