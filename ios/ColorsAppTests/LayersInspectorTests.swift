// Inspector de capas sobre la escena sintética con una persona
// (SyntheticPersonScene, la de -uiScreen layers-demo):
//  - la escena y la máscara de su cadena (persona principal + solo ropa + piel)
//    son byte a byte las fixtures Fixtures/layers/layers_demo.ppm y
//    layers_demo.mask.pgm (make ios-layers-fixtures las regenera);
//  - el inspector construye 11 capas en orden, con mapa de bits en las de imagen;
//  - el swatch por píxel (capa 9) y la tabla de "por qué ganó" (capa 11)
//    coinciden con `ce match layers_demo.ppm --mask layers_demo.mask.pgm --top 3
//    --json --debug-dir` sobre el mismo raster (labels.pgm y debug.json copiados a
//    Fixtures/layers/ como layers_demo.labels.pgm y layers_demo.debug.json);
//  - "Compartir capas" renderiza el PNG vertical (se guarda en COLORSAPP_SCREENS_DIR).
import XCTest
import SwiftUI
import UIKit
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class LayersInspectorTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: LayersInspectorTests.self) }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext),
                                "\(name).\(ext) en el bundle (Fixtures/layers; make ios-layers-fixtures)")
        return try Data(contentsOf: url)
    }

    private func pgm(_ data: Data) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let parsed = try XCTUnwrap(PNM.read(data), "PGM ilegible")
        XCTAssertEqual(parsed.channels, 1)
        return (parsed.width, parsed.height, parsed.bytes)
    }

    /// La cadena por defecto de la app sobre la escena.
    private func demoChain(_ scene: SyntheticPersonScene) throws -> SubjectMaskResult {
        let raster = try EngineBridge.rasterize(try XCTUnwrap(scene.image))
        return try raster.pixels.withUnsafeBufferPointer { px in
            try SubjectExtractor.mask(people: [scene.person], rgba: px, width: raster.width, height: raster.height,
                                      stride: raster.stride, options: .default)
        }
    }

    func testDemoSceneMatchesFixtures() throws {
        let scene = SyntheticPersonScene.make()
        let chain = try demoChain(scene)
        let mask = try XCTUnwrap(chain.mask)
        XCTAssertEqual(chain.steps, [.poseRegions, .skinExcluded])
        if let out = ProcessInfo.processInfo.environment["COLORSAPP_LAYERS_FIXTURES_OUT"], !out.isEmpty {
            let dir = URL(fileURLWithPath: out, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try PPM.write(scene.ppm).write(to: dir.appendingPathComponent("layers_demo.ppm"))
            try PNM.pgm(width: scene.width, height: scene.height, gray: mask).write(to: dir.appendingPathComponent("layers_demo.mask.pgm"))
            print("LayersInspectorTests: fixtures de entrada escritas en \(dir.path)")
        }
        let ppm = try PPM.parse(try fixture("layers_demo", "ppm"))
        XCTAssertEqual(ppm, scene.ppm, "SyntheticPersonScene cambió: make ios-layers-fixtures")
        let maskFixture = try pgm(try fixture("layers_demo.mask", "pgm"))
        XCTAssertEqual(maskFixture.width, scene.width)
        XCTAssertEqual(maskFixture.bytes, mask, "la cadena de máscaras cambió: make ios-layers-fixtures")
    }

    func testInspectorBuildsElevenLayersAndMatchesCLI() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let ppm = try PPM.parse(try fixture("layers_demo", "ppm"))
        let image = try XCTUnwrap(ppm.makeCGImage())
        let maskFixture = try pgm(try fixture("layers_demo.mask", "pgm"))
        // La máscara de la fixture como "persona completa" sin piel: la máscara que
        // recibe el motor es exactamente la del --mask del CLI.
        let person = PersonInstance(id: 1, mask: maskFixture.bytes, width: ppm.width, height: ppm.height)
        let options = SubjectOptions(mode: .largestPerson, region: .wholePerson, adaptiveSkin: false)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-layers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = try await ScanAnalyzer.run(image: image, source: .manual, subject: options, people: [person], env: env,
                                                 timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
        XCTAssertEqual(outcome.raster.rgb, ppm.rgb, "raster == PPM byte a byte")
        XCTAssertEqual(outcome.subject.mask, maskFixture.bytes)
        let debug = try XCTUnwrap(outcome.debug)

        // 11 capas en orden, con imagen en las que se superponen.
        let dictionary = env.dictionary
        let stack = await Task.detached { LayerStack.build(outcome: outcome, dictionary: dictionary) }.value
        XCTAssertEqual(stack.layers.count, 11)
        XCTAssertEqual(stack.layers.map(\.kind), InspectorLayer.Kind.allCases)
        XCTAssertEqual(stack.layers.map(\.number), Array(1...11))
        XCTAssertEqual(stack.layers.map(\.title), ["Foto", "Lo que ve el motor", "Imagen reducida", "Personas detectadas",
                                                   "Pose y región de ropa", "Piel excluida", "Máscara final",
                                                   "Peso por píxel", "Asignación a colores", "Paleta final", "Por qué ganó"])
        XCTAssertTrue(stack.layers.allSatisfy { !$0.meaning.isEmpty })
        for kind in [InspectorLayer.Kind.raster, .reduced, .people, .finalMask, .weights, .labels] {
            XCTAssertNotNil(stack.layer(kind)?.overlay, "capa \(kind.rawValue) con imagen")
        }
        XCTAssertEqual(stack.layer(.reduced)?.overlay?.width, debug.debug.reducedWidth)
        XCTAssertEqual(stack.swatches.count, outcome.result.swatches.count)
        XCTAssertEqual(stack.explanations.count, 3)

        // Capa 9 == labels.pgm del CLI.
        let labels = try pgm(try fixture("layers_demo.labels", "pgm"))
        XCTAssertEqual(labels.width, debug.debug.reducedWidth)
        XCTAssertEqual(labels.height, debug.debug.reducedHeight)
        XCTAssertEqual(stack.labelMap, labels.bytes, "swatch por píxel idéntico al del CLI")

        // Capa 11 == explain de debug.json del CLI.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("layers_demo.debug", "json")) as? [String: Any])
        let hits = try XCTUnwrap(json["hits"] as? [[String: Any]])
        XCTAssertEqual(outcome.result.hits.map(\.comboId), hits.compactMap { $0["id"] as? Int })
        let explain = try XCTUnwrap(json["explain"] as? [[String: Any]])
        XCTAssertEqual(explain.count, stack.explanations.count)
        var maxDiff = 0.0
        func close(_ a: Double, _ b: Any?, _ what: String) {
            guard let b = (b as? NSNumber)?.doubleValue else { return XCTFail("\(what): falta en debug.json") }
            maxDiff = max(maxDiff, abs(a - b))
            XCTAssertEqual(a, b, accuracy: 1e-9, what)
        }
        for (card, e) in zip(stack.explanations, explain) {
            XCTAssertEqual(card.rank, e["rank"] as? Int)
            XCTAssertEqual(card.comboId, e["id"] as? Int)
            close(card.score, e["score"], "score \(card.comboId)")
            close(card.fitTerm, e["fit_term"], "fit_term \(card.comboId)")
            close(card.coverageTerm, e["coverage_term"], "coverage_term \(card.comboId)")
            close(card.hypothesisPenalty, e["hypothesis_penalty"], "hypothesis_penalty \(card.comboId)")
            close(card.exposureEV, e["exposure_ev"], "exposure_ev \(card.comboId)")
            XCTAssertEqual(card.illuminant, e["illuminant"] as? Int)
            XCTAssertEqual(DiagnosticsSubject.illuminantName(card.illuminant), e["illuminant_name"] as? String)
            let perSwatch = try XCTUnwrap(e["per_swatch"] as? [[String: Any]])
            XCTAssertEqual(card.swatchLines.count, perSwatch.count)
            for (line, p) in zip(card.swatchLines, perSwatch) {
                XCTAssertEqual(line.colorIndex, p["nearest_color"] as? Int, "combo \(card.comboId) swatch \(line.swatch)")
                close(line.deltaE, p["de"], "ΔE swatch \(line.swatch) combo \(card.comboId)")
                XCTAssertEqual(line.colorHex.lowercased(), (p["nearest_color_hex"] as? String)?.lowercased())
            }
            let perColor = try XCTUnwrap(e["per_color"] as? [[String: Any]])
            XCTAssertEqual(card.colorLines.map(\.colorIndex), perColor.compactMap { $0["color"] as? Int })
            XCTAssertEqual(card.colorLines.map(\.nearestSwatch), perColor.compactMap { $0["nearest_swatch"] as? Int })
            for (line, p) in zip(card.colorLines, perColor) {
                close(line.deltaE, p["de"], "ΔE color \(line.colorIndex) combo \(card.comboId)")
                XCTAssertEqual(line.colorName, p["name"] as? String)
            }
        }
        // Clusters y su destino == palette_debug del CLI; debug.json de la app con los mismos nombres.
        let paletteDebug = try XCTUnwrap(json["palette_debug"] as? [String: Any])
        let clusters = try XCTUnwrap(paletteDebug["clusters"] as? [[String: Any]])
        XCTAssertEqual(debug.debug.clusters.map(\.fate.rawValue), clusters.compactMap { $0["fate"] as? Int })
        XCTAssertEqual(debug.debug.clusters.map(\.hex), clusters.compactMap { $0["hex"] as? String })
        let ours = DiagnosticsSubject.debugJSON(debug)
        XCTAssertEqual((ours["label_counts"] as? [String: Int]), (json["label_counts"] as? [String: Int]))
        XCTAssertEqual(((ours["palette_debug"] as? [String: Any])?["clusters"] as? [[String: Any]])?.compactMap { $0["pixels"] as? Int },
                       clusters.compactMap { $0["pixels"] as? Int })
        print(String(format: "LayersInspectorTests: 11 capas; label map %dx%d idéntico al CLI; explicación top-3 máx |Δ| = %.3g", labels.width, labels.height, maxDiff))

        // Aislar un swatch; PNG de "Compartir capas".
        let model = LayersInspectorModel(outcome: outcome, dictionary: env.dictionary)
        await model.load()
        XCTAssertEqual(model.stack?.layers.count, 11)
        model.toggleIsolation(0)
        XCTAssertEqual(model.isolatedSwatch, 0)
        XCTAssertNotNil(model.isolatedOverlay)
        model.toggleIsolation(0)
        XCTAssertNil(model.isolatedSwatch)
        let url = try XCTUnwrap(model.shareURL, "PNG de Compartir capas")
        let png = try Data(contentsOf: url)
        let rendered = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(rendered.width, Int(LayersShareSheet.width * LayersShareSheet.renderScale))
        XCTAssertGreaterThan(rendered.height, rendered.width * 2, "vertical: todas las capas")
        try saveScreen(png, name: "layers-share-synthetic.png")
    }

    func testDemoLayersWithRealChain() async throws {
        // La escena con la cadena de la app (persona principal + solo ropa + piel):
        // capas 4–7 con pose, región y piel quitada; guarda la hoja de capas para revisarla.
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let scene = SyntheticPersonScene.make()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-layers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = try await ScanAnalyzer.run(image: try XCTUnwrap(scene.image), source: .manual, subject: .default,
                                                 people: [scene.person], env: env,
                                                 timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
        let stack = LayerStack.build(outcome: outcome, dictionary: env.dictionary)
        XCTAssertEqual(stack.layers.count, 11)
        XCTAssertEqual(stack.poses.count, 1, "esqueleto de la persona elegida")
        for kind in InspectorLayer.Kind.allCases where ![.photo, .palette, .explanation].contains(kind) {
            XCTAssertNotNil(stack.layer(kind)?.overlay, "capa \(kind.rawValue) con imagen")
            XCTAssertNil(stack.layer(kind)?.warning, "capa \(kind.rawValue) sin aviso: \(stack.layer(kind)?.warning ?? "")")
        }
        let skinFact = try XCTUnwrap(stack.layer(.skin)?.facts.first)
        XCTAssertTrue(skinFact.contains("px de piel quitados"), skinFact)
        XCTAssertEqual(stack.notice.text, "Solo ropa · piel excluida")
        let image = try XCTUnwrap(LayersShareRenderer.render(stack: stack, title: "Escena sintética"))
        try saveScreen(try XCTUnwrap(image.pngData()), name: "layers-share-demo.png")
    }

    private func saveScreen(_ png: Data, name: String) throws {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["COLORSAPP_SCREENS_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("LayersInspectorTests: \(url.path)")
    }
}
