// Pestaña Extraer y resultado (ExtractView / ExtractResultContent / ResultViewModel) y visor de
// capas tipo historias, sobre la escena sintética con una persona (la de -uiScreen layers-demo,
// cadena real: persona principal + solo ropa + piel):
//  - un alfiler por color de la paleta, en un píxel del label map que pertenece a ese color, con
//    el nombre del color de Wada más cercano (motor) y su peso;
//  - «Copiar hex» y copiar un color escriben los hex en mayúsculas en el portapapeles;
//  - «Guardar en el jardín» usa GardenStore (en memoria) y se refleja al reabrir el resultado;
//  - aislar un swatch crea la capa de la imagen reducida y soltar la quita;
//  - top-3 con nombres (aceptado → propuesto → «Nº 012») y aviso de recorte = SubjectExplanation;
//  - visor de capas: capa inicial desde -uiLayer y tercios de toque (anterior / siguiente);
//  - las vistas se construyen en claro y oscuro con ImageRenderer sin romperse.
import XCTest
import SwiftUI
import UIKit
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class ExtractViewTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-extract-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func demoOutcome(env: AppEnvironment) async throws -> ScanOutcome {
        let scene = SyntheticPersonScene.make()
        return try await ScanAnalyzer.run(image: try XCTUnwrap(scene.image), source: .manual, subject: .default,
                                          people: [scene.person], env: env,
                                          timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
    }

    func testPinsSitOnTheirSwatchPixelsWithNearestWadaNames() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let outcome = try await demoOutcome(env: env)
        let model = ResultViewModel(outcome: outcome, env: env, garden: GardenStore(url: nil))
        await model.load()
        let debug = try XCTUnwrap(outcome.debug)
        XCTAssertEqual(model.palette.count, outcome.result.swatches.count)
        XCTAssertFalse(model.pins.isEmpty)
        XCTAssertEqual(model.pins.map(\.id), model.palette.map(\.id), "un alfiler por color con píxeles")
        for pin in model.pins {
            let x = Int(pin.position.x * Double(debug.debug.reducedWidth))
            let y = Int(pin.position.y * Double(debug.debug.reducedHeight))
            XCTAssertEqual(Int(debug.labelMap[y * debug.debug.reducedWidth + x]), pin.id, "alfiler \(pin.id) sobre su color")
            let swatch = outcome.result.swatches[pin.id]
            let nearest = nearestDictionaryColor(swatch.lab)
            XCTAssertEqual(pin.title, env.dictionary.color(index: nearest.index)?.name)
            XCTAssertEqual(pin.detail, DesignFormat.percent(swatch.weight))
            XCTAssertEqual(model.palette[pin.id].deltaE ?? -1, nearest.deltaE, accuracy: 1e-12)
        }
        XCTAssertEqual(model.maskNotice, SubjectExplanation.notice(options: outcome.subjectOptions, result: outcome.subject))
        XCTAssertEqual(model.maskNotice.text, "Solo ropa · piel excluida")
        XCTAssertEqual(model.paletteTitle, "Colores de la ropa")
        XCTAssertTrue(model.paletteSummary.hasPrefix("\(model.palette.count) colores · "), model.paletteSummary)
        XCTAssertTrue(model.paletteSummary.hasSuffix("de la foto"), model.paletteSummary)
        print("ExtractViewTests: alfileres \(model.pins.map { "\($0.title) \($0.detail ?? "") (\(String(format: "%.3f", $0.position.x)), \(String(format: "%.3f", $0.position.y)))" })")
    }

    func testCopySaveIsolateAndMatches() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let outcome = try await demoOutcome(env: env)
        let garden = GardenStore(url: nil)
        let model = ResultViewModel(outcome: outcome, env: env, garden: garden)
        await model.load()
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        let toast = model.copyPalette(pasteboard: pasteboard)
        let expected = outcome.result.swatches.map { $0.hex.uppercased() }.joined(separator: " ")
        XCTAssertEqual(pasteboard.string, expected)
        XCTAssertEqual(toast, model.palette.count == 1 ? "Copiado \(expected)" : "Copiados \(model.palette.count) hex")
        let first = try XCTUnwrap(model.palette.first)
        XCTAssertEqual(model.copy(first, pasteboard: pasteboard), "Copiado \(first.hex)")
        XCTAssertEqual(pasteboard.string, first.hex)
        XCTAssertEqual(model.selectedSwatch, first.id)

        XCTAssertFalse(model.isSaved)
        XCTAssertEqual(model.toggleSave(), "Guardado en el Jardín")
        XCTAssertTrue(garden.isSaved(scanId: outcome.scan.id))
        XCTAssertTrue(ResultViewModel(outcome: outcome, env: env, garden: garden).isSaved, "se ve guardado al reabrir")
        XCTAssertEqual(model.toggleSave(), "Quitado del Jardín")
        XCTAssertFalse(garden.isSaved(scanId: outcome.scan.id))

        let debug = try XCTUnwrap(outcome.debug)
        model.setIsolation(first.id, active: true)
        XCTAssertEqual(model.isolatedSwatch, first.id)
        XCTAssertEqual(model.isolationOverlay?.width, debug.debug.reducedWidth)
        XCTAssertEqual(model.isolationOverlay?.height, debug.debug.reducedHeight)
        model.setIsolation(first.id, active: false)
        XCTAssertNil(model.isolatedSwatch)
        XCTAssertNil(model.isolationOverlay)

        let matches = model.matches
        XCTAssertEqual(matches.map(\.comboId), outcome.result.hits.map(\.comboId))
        XCTAssertEqual(matches.first?.name, ComboNaming.bundled.name(for: matches[0].comboId, in: env.dictionary).text)
        XCTAssertEqual(matches.first?.colors.count, env.dictionary.colors(ofComboId: matches[0].comboId).count)
        XCTAssertTrue(model.technicalFooter.hasPrefix("Motor \(outcome.scan.engineVersion) · diccionario"), model.technicalFooter)
    }

    func testMaskToggleIsOffWithoutMask() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let outcome = try await ScanAnalyzer.run(image: image, source: .manual, subject: SubjectOptions(mode: .off), env: env,
                                                 timing: TimingLog(url: dir.appendingPathComponent("t.txt")))
        let model = ResultViewModel(outcome: outcome, env: env, garden: GardenStore(url: nil))
        model.showMask = true
        await model.load()
        XCTAssertNil(model.maskOverlay)
        XCTAssertFalse(model.showMask, "sin máscara el conmutador vuelve a «Ver máscara»")
        XCTAssertEqual(model.paletteTitle, "Colores de la foto")
        XCTAssertEqual(model.paletteSummary, "2 colores · foto completa")
        XCTAssertEqual(model.maskNotice.text, "Recorte desactivado: foto completa")
    }

    func testViewfinderKeepsPinsClearOfTheHUDWhenThePhotoFits() {
        // 5:4 (escena de dos personas): la foto va entre las franjas del HUD.
        let wide = ExtractViewfinder.layout(aspect: 1.25, width: 370)
        XCTAssertEqual(wide.height, 400)
        XCTAssertEqual(wide.top, ExtractViewfinder.hudTop)
        XCTAssertEqual(wide.bottom, ExtractViewfinder.hudBottom)
        // 16:9: marco más bajo, foto a todo el ancho entre las franjas.
        let panorama = ExtractViewfinder.layout(aspect: 16.0 / 9.0, width: 370)
        XCTAssertEqual(panorama.height, 370 / (16.0 / 9.0) + ExtractViewfinder.hudTop + ExtractViewfinder.hudBottom, accuracy: 1e-9)
        XCTAssertGreaterThan(panorama.top, 0)
        // 3:4 (foto de grupo vertical): entre las franjas quedaría estrecha; ocupa el marco de 400 pt.
        let portrait = ExtractViewfinder.layout(aspect: 772.0 / 1024.0, width: 370)
        XCTAssertEqual(portrait.height, Sizes.viewfinderMaxHeight)
        XCTAssertEqual(portrait.top, 0)
        XCTAssertEqual(portrait.bottom, 0)
    }

    func testStoriesNavigation() {
        XCTAssertEqual(LayersInspectorView.startIndex(initialLayer: nil, count: 11), 0)
        XCTAssertEqual(LayersInspectorView.startIndex(initialLayer: 6, count: 11), 5)
        XCTAssertEqual(LayersInspectorView.startIndex(initialLayer: 40, count: 11), 10)
        XCTAssertEqual(LayersInspectorView.index(afterTapAt: 50, width: 390, current: 4, count: 11), 3, "tercio izquierdo: anterior")
        XCTAssertEqual(LayersInspectorView.index(afterTapAt: 200, width: 390, current: 4, count: 11), 5, "resto: siguiente")
        XCTAssertEqual(LayersInspectorView.index(afterTapAt: 10, width: 390, current: 0, count: 11), 0)
        XCTAssertEqual(LayersInspectorView.index(afterTapAt: 380, width: 390, current: 10, count: 11), 10)
    }

    func testResultAndStoriesRenderInLightAndDark() async throws {
        let env = try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
        let outcome = try await demoOutcome(env: env)
        let model = ResultViewModel(outcome: outcome, env: env, garden: GardenStore(url: nil))
        await model.load()
        let layers = LayersInspectorModel(outcome: outcome, dictionary: env.dictionary)
        await layers.load()
        let stack = try XCTUnwrap(layers.stack)
        for scheme in [ColorScheme.light, .dark] {
            let content = ExtractResultContent(model: model, onOpenLayers: { _ in }, toast: .constant(nil))
                .environmentObject(env)
                .padding(16)
                .frame(width: 402)
                .background(Theme.surface)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, "resultado en \(scheme)")
            XCTAssertEqual(image.size.width, 402)
            XCTAssertGreaterThan(image.size.height, 900)
            for layer in stack.layers {
                let panel = StoryLayerPanel(layer: layer, stack: stack, model: layers, count: stack.layers.count)
                    .frame(width: 402)
                    .environment(\.colorScheme, .dark)
                let r = ImageRenderer(content: panel)
                XCTAssertNotNil(r.uiImage, "panel de la capa \(layer.number)")
            }
        }
    }
}
