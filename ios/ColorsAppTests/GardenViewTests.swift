// Pestaña Jardín, Ajustes y resumen del escaneo con el sistema de diseño
// (docs/design/DESIGN_SYSTEM.md §5.4): «Guardar» local (GardenStore), contadores reales
// sobre una base de datos en memoria, colecciones por tamaño, textos en español, tarjeta
// compartible 1080 × 1350 de una cosecha y construcción de las vistas en claro y oscuro.
// Con TEST_RUNNER_COLORSAPP_GARDEN_SCREENS_DIR guarda capturas de las vistas con los datos de
// ejemplo de DEBUG (GardenDemo) como respaldo de las capturas del simulador.
import XCTest
import SwiftUI
import UIKit
import ImageIO
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class GardenViewTests: XCTestCase {

    // MARK: GardenStore

    func testGardenStorePersistsTogglesAndPrunes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("garden-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(GardenStore.fileName)
        let store = GardenStore(url: url)
        XCTAssertTrue(store.items.isEmpty)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(store.toggle(scanId: "scan-a", now: t0))
        XCTAssertTrue(store.toggle(comboId: 67, now: t0.addingTimeInterval(10)))
        store.save(scanId: "scan-b", now: t0.addingTimeInterval(20))
        store.save(scanId: "scan-b", now: t0.addingTimeInterval(30)) // idempotente
        XCTAssertEqual(store.items.map(\.key), ["scan:scan-b", "combo:67", "scan:scan-a"], "más reciente primero")
        XCTAssertTrue(store.isSaved(scanId: "scan-a"))
        XCTAssertTrue(store.isSaved(comboId: 67))
        XCTAssertFalse(store.isSaved(comboId: 68))
        XCTAssertNil(store.lastError)

        // Otra instancia lee el mismo fichero.
        let reloaded = GardenStore(url: url)
        XCTAssertEqual(reloaded.items.map(\.key), store.items.map(\.key))
        XCTAssertEqual(reloaded.savedScanIds, ["scan-a", "scan-b"])
        XCTAssertEqual(reloaded.savedComboIds, [67])
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(json.contains("\"kind\" : \"combo\""), json)
        XCTAssertTrue(json.contains("\"version\" : 1"), json)

        XCTAssertFalse(reloaded.toggle(scanId: "scan-a"), "segundo toque: se quita")
        reloaded.prune(liveScanIds: [])
        XCTAssertEqual(reloaded.items.map(\.key), ["combo:67"])
        XCTAssertEqual(GardenStore(url: url).items.map(\.key), ["combo:67"])

        let memory = GardenStore(url: nil)
        memory.save(scanId: "x")
        XCTAssertTrue(memory.isSaved(scanId: "x"))
    }

    // MARK: Textos

    func testGardenTextsAreSpanishAndReal() throws {
        XCTAssertEqual(GardenText.accuracy(yes: 0, no: 0), "Vota tus resultados para ver el acierto")
        XCTAssertEqual(GardenText.accuracy(yes: 41, no: 9), "Acierto: 82\u{00A0}% (41 de 50 votos)")
        XCTAssertEqual(GardenText.accuracy(yes: 1, no: 0), "Acierto: 100\u{00A0}% (1 de 1 voto)")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 18, minute: 30)))
        let morning = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10, minute: 45)))
        XCTAssertEqual(GardenText.relativeDay(morning, now: now, calendar: cal), "hoy, 10:45")
        XCTAssertEqual(GardenText.relativeDay(now.addingTimeInterval(-86_400), now: now, calendar: cal), "ayer")
        XCTAssertEqual(GardenText.relativeDay(now.addingTimeInterval(-3 * 86_400), now: now, calendar: cal), "hace 3 días")
        let old = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 12)))
        XCTAssertTrue(GardenText.relativeDay(old, now: now, calendar: cal).hasPrefix("2 ago"),
                      GardenText.relativeDay(old, now: now, calendar: cal))
        let lastYear = try XCTUnwrap(cal.date(from: DateComponents(year: 2025, month: 12, day: 24, hour: 12)))
        XCTAssertTrue(GardenText.relativeDay(lastYear, now: now, calendar: cal).contains("2025"))

        XCTAssertEqual(GardenText.sourceTitle(.library), "Carrete")
        XCTAssertEqual(GardenText.sourceTitle(.camera), "Cámara")
        XCTAssertEqual(GardenText.sourceTitle(.picker), "Foto elegida")
        XCTAssertEqual(GardenText.savedCount(1), "1 guardada")
        XCTAssertEqual(GardenText.savedCount(5), "5 guardadas")
        XCTAssertEqual(GardenExport.copiedToast(count: 1, single: "#222524"), "Copiado #222524")
        XCTAssertEqual(GardenExport.copiedToast(count: 5, single: "#222524"), "Copiados 5 hex")
        XCTAssertEqual(GardenExport.fileSlug(AppBrand.name), "chromasol")
        XCTAssertEqual(AjustesForm.thresholdText(12), "12,0")
        XCTAssertEqual(WrappedSummaryView.counterText(unlocked: 20, total: 348), "20/348")

        let env = try AppEnvironment.forTesting()
        let names = env.dictionary.colors(ofComboId: 27).prefix(2).map(\.name)
        XCTAssertEqual(GardenText.comboTitle(27, dictionary: env.dictionary, naming: .empty),
                       env.dictionary.curatedName(id: 27) ?? names.joined(separator: " · "))
        let proposed = ComboNaming(proposed: [27: "Rosa y pizarra"])
        XCTAssertEqual(GardenText.comboTitle(27, dictionary: env.dictionary, naming: proposed),
                       env.dictionary.curatedName(id: 27) ?? "Rosa y pizarra")
        XCTAssertEqual(GardenText.comboTitle(nil, dictionary: env.dictionary), "Sin resultado")
    }

    /// Textos de la fidelidad al ejemplo (FIDELITY.md §6) y movimiento de las luciérnagas (M18).
    func testGardenFidelityTextsAndFireflies() throws {
        XCTAssertNil(GardenText.accuracyParts(yes: 0, no: 0))
        let parts = try XCTUnwrap(GardenText.accuracyParts(yes: 41, no: 9))
        XCTAssertEqual(parts.label, "Acierto:")
        XCTAssertEqual(parts.value, "82\u{00A0}% (41 de 50 votos)")
        XCTAssertEqual("\(parts.label) \(parts.value)", GardenText.accuracy(yes: 41, no: 9))
        XCTAssertEqual(GardenText.accuracyParts(yes: 1, no: 0)?.value, "100\u{00A0}% (1 de 1 voto)")

        let black = try XCTUnwrap(PaletteColor(id: 0, hex: "#16171D", name: "Black", weight: 0.333))
        let gray = try XCTUnwrap(PaletteColor(id: 1, hex: "#9A9897", weight: 0.667))
        XCTAssertEqual(GardenText.dominantLine(black), "Dominante: Black (#16171D) · 33\u{00A0}%")
        XCTAssertEqual(GardenText.dominantLine(gray), "Dominante: #9A9897 · 67\u{00A0}%")
        XCTAssertEqual(GardenText.distribution([black, gray]), "33\u{00A0}% Black · 67\u{00A0}%")
        XCTAssertEqual(GardenText.newUnlocks(current: 20, lastSeen: 17), 3)
        XCTAssertEqual(GardenText.newUnlocks(current: 5, lastSeen: 9), 0, "nunca negativo")
        XCTAssertEqual(GardenText.newUnlocks(current: 4, lastSeen: -2), 4)

        XCTAssertEqual(GardenHarvestCard.Variant.forIndex(0), .droplets)
        XCTAssertEqual(GardenHarvestCard.Variant.forIndex(1), .strip)
        XCTAssertEqual(GardenHarvestCard.Variant.forIndex(2), .distribution)
        XCTAssertEqual(GardenHarvestCard.Variant.forIndex(3), .strip)

        // Luciérnagas: posiciones del HTML (top-3 right-16 / bottom-6 left-12 / top-10 left-2), 4 s, retrasos 0 / 1,5 / 2,4 s.
        let flies = GardenMotion.fireflies
        XCTAssertEqual(flies.map(\.size), [8, 6, 8])
        XCTAssertEqual(flies.map(\.clock.delay), [0, 1.5, 2.4])
        let card = CGSize(width: 370, height: 160)
        XCTAssertEqual(flies[0].restCenter(in: card), CGPoint(x: 370 - 64 - 4, y: 12 + 4))
        XCTAssertEqual(flies[1].restCenter(in: card), CGPoint(x: 48 + 3, y: 160 - 24 - 3))
        XCTAssertEqual(flies[2].restCenter(in: card), CGPoint(x: 8 + 4, y: 40 + 4))
        let rest = GardenMotion.firefly(flies[0], at: nil)
        XCTAssertEqual(rest.offset, .zero)
        XCTAssertEqual(rest.opacity, 0.4, accuracy: 1e-9)
        let peak = GardenMotion.firefly(flies[0], at: 2)
        XCTAssertEqual(peak.offset.x, 3, accuracy: 1e-6)
        XCTAssertEqual(peak.offset.y, -6, accuracy: 1e-6)
        XCTAssertEqual(peak.opacity, 1, accuracy: 1e-6)
        let delayed = GardenMotion.firefly(flies[2], at: 1)
        XCTAssertEqual(delayed.offset, .zero, "durante el retraso queda en su sitio")
        XCTAssertEqual(GardenMotion.firefly(flies[1], at: 1.5 + 4).opacity, 0.4, accuracy: 1e-6)
    }

    // MARK: Modelo con base de datos

    func testGardenModelCountsCollectionsAndSaved() async throws {
        let env = try AppEnvironment.forTesting()
        let store = GardenStore(url: nil)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var ids: [String] = []
        for (i, combo) in [27, 152, 254].enumerated() {
            let image = try XCTUnwrap(SyntheticImage.blocks(comboId: combo, dictionary: env.dictionary))
            let analysis = try ScanAnalyzer.analyze(image: image, subject: SubjectOptions(mode: .off), layers: false)
            let scan = ScanRecord.make(from: analysis.result, source: i == 0 ? .camera : .library,
                                       now: t0.addingTimeInterval(Double(i) * 3600))
            try await env.scans.insert(scan)
            ids.append(scan.id)
        }
        try await env.feedback.record(scanId: ids[0], verdict: .no, at: t0)
        try await env.feedback.record(scanId: ids[0], verdict: .yes, at: t0.addingTimeInterval(5))
        try await env.feedback.record(scanId: ids[1], verdict: .yes, at: t0)
        try await env.unlocks.unlock(comboId: 27, source: .library, at: t0)
        try await env.unlocks.unlock(comboId: 12, source: .manual, at: t0.addingTimeInterval(100))
        try await env.unlocks.unlock(comboId: 152, source: .library, at: t0.addingTimeInterval(50))
        store.save(scanId: ids[0])
        store.toggle(comboId: 337)

        let model = GardenModel()
        await model.refresh(env: env, store: store)
        XCTAssertTrue(model.loaded)
        XCTAssertEqual(model.scanCount, 3)
        XCTAssertEqual(model.scans.map(\.id), ids.reversed(), "más reciente primero")
        XCTAssertEqual(model.latestScan?.id, ids[2])
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.yesVotes, 2)
        XCTAssertEqual(model.noVotes, 1)
        XCTAssertEqual(model.verdict(for: model.scans[2]), .yes, "cuenta el último veredicto")
        XCTAssertNil(model.verdict(for: model.scans[0]))
        XCTAssertEqual(model.unlocks.count, 3)
        XCTAssertEqual(model.savedScans.map(\.id), [ids[0]])

        let collections = model.sizeCollections(env.dictionary)
        XCTAssertEqual(collections.map(\.size), [2, 3, 4])
        XCTAssertEqual(collections.map(\.total).reduce(0, +), 348)
        let bySize = Dictionary(uniqueKeysWithValues: collections.map { ($0.size, $0) })
        let size27 = try XCTUnwrap(env.dictionary.combo(id: 27)?.size)
        let size12 = try XCTUnwrap(env.dictionary.combo(id: 12)?.size)
        XCTAssertTrue(bySize[size27]?.recentUnlocked.contains(27) ?? false)
        XCTAssertTrue(bySize[size12]?.recentUnlocked.contains(12) ?? false)
        XCTAssertEqual(collections.map(\.unlocked).reduce(0, +), 3)
        if size27 == size12 {
            XCTAssertEqual(bySize[size12]?.recentUnlocked.first, 12, "más reciente primero")
        }
        XCTAssertEqual(bySize[2]?.countText, "\(bySize[2]?.unlocked ?? -1)/\(bySize[2]?.total ?? -1)")

        // Paleta de la cosecha: colores de datos con el nombre de Wada del motor, hex en mayúsculas.
        let scan = model.scans[0]
        let palette = model.palette(for: scan, dictionary: env.dictionary)
        XCTAssertEqual(palette.count, scan.palette.count)
        XCTAssertFalse(palette.isEmpty)
        for c in palette {
            XCTAssertNotNil(c.name)
            XCTAssertEqual(c.hex, c.hex.uppercased())
        }
        XCTAssertEqual(GardenExport.hexList(scan), palette.map(\.hex).joined(separator: " "))
        XCTAssertEqual(GardenText.harvestTags(scan).first, scan.top1.map(WadaDictionary.numberLabel))
        XCTAssertTrue(GardenText.harvestMetadata(scan, now: t0.addingTimeInterval(86_400 * 30), isExample: true).hasSuffix("Carrete · Ejemplo"))

        // Paginación: con límite 2 hay más.
        model.limit = 2
        await model.refresh(env: env, store: store)
        XCTAssertEqual(model.scans.count, 2)
        XCTAssertTrue(model.hasMore)

        // Un scan borrado desaparece de las guardadas.
        try await env.scans.softDelete(id: ids[0])
        await model.refresh(env: env, store: store)
        XCTAssertTrue(model.savedScans.isEmpty)
    }

    // MARK: Tarjeta

    func testShareCardOfHarvestIs1080x1350PNG() async throws {
        let env = try AppEnvironment.forTesting()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 67, dictionary: env.dictionary))
        let analysis = try ScanAnalyzer.analyze(image: image, subject: SubjectOptions(mode: .off), layers: false)
        let scan = ScanRecord.make(from: analysis.result, source: .picker)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("garden-card-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try GardenExport.writeCard(for: scan, photo: image, dictionary: env.dictionary, directory: dir)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("chromasol-tarjeta-"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let png = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(png.width, 1080)
        XCTAssertEqual(png.height, 1350)
        let thumb = GardenPhotos.downscaled(image, maxSide: 64)
        XCTAssertEqual(max(thumb.width, thumb.height), 64)
    }

    // MARK: Vistas

    func testGardenAjustesAndWrappedViewsBuildInBothThemes() async throws {
        let env = try AppEnvironment.forTesting()
        let seeded = try await GardenDemo.seed(dictionary: env.dictionary, launches: 0)
        let demoScans = try await seeded.env.scans.count()
        let demoUnlocks = try await seeded.env.unlocks.count()
        XCTAssertGreaterThanOrEqual(demoScans, 4)
        XCTAssertGreaterThanOrEqual(demoUnlocks, GardenDemo.extraUnlocks.count)
        XCTAssertFalse(seeded.store.items.isEmpty)
        XCTAssertGreaterThan(seeded.summary.scanned, 0)
        for scheme in [ColorScheme.light, .dark] {
            for segment in GardenModel.Segment.allCases {
                let garden = GardenScreen(store: seeded.store, photos: seeded.photos, isExample: true, initialSegment: segment)
                    .environmentObject(seeded.env)
                    .environment(\.colorScheme, scheme)
                let host = UIHostingController(rootView: garden)
                XCTAssertGreaterThan(host.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100, "\(segment) \(scheme)")
            }
            let empty = UIHostingController(rootView: GardenScreen(store: GardenStore(url: nil)).environmentObject(env)
                .environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(empty.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
            let ajustes = UIHostingController(rootView: NavigationStack { AjustesForm() }.environmentObject(env)
                .environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(ajustes.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
            let about = UIHostingController(rootView: NavigationStack { AboutView() }.environmentObject(env)
                .environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(about.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
            let wrapped = UIHostingController(rootView: WrappedSummaryView(summary: seeded.summary, dictionary: env.dictionary,
                                                                           totalCombos: env.comboCount, onShowGrid: {})
                .environment(\.colorScheme, scheme))
            XCTAssertGreaterThan(wrapped.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
        }
        XCTAssertTrue(AboutView.credits.contains { $0.text.contains("SIL Open Font License 1.1") && $0.text.contains("Literata") })
        XCTAssertTrue(AboutView.credits.contains { $0.text.contains("Plus Jakarta Sans") })
        XCTAssertTrue(GardenDemoLaunch.isRequested(in: ["app", "-uiScreen", "jardin-demo"]))
        XCTAssertTrue(GardenDemoLaunch.isRequested(in: ["app", "-uiScreen", "jardin", "-uiGardenDemo", "1"]))
        XCTAssertFalse(GardenDemoLaunch.isRequested(in: ["app", "-uiScreen", "jardin"]))
    }

    /// Capturas de respaldo (drawHierarchy en la ventana de la app) si se pide un directorio.
    func testCaptureGardenScreensWhenRequested() async throws {
        guard let dir = ProcessInfo.processInfo.environment["COLORSAPP_GARDEN_SCREENS_DIR"], !dir.isEmpty else {
            throw XCTSkip("COLORSAPP_GARDEN_SCREENS_DIR no definido")
        }
        let env = try AppEnvironment.forTesting()
        let seeded = try await GardenDemo.seed(dictionary: env.dictionary, launches: 0)
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for scheme in [UIUserInterfaceStyle.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let screen = GardenScreen(store: seeded.store, photos: seeded.photos, isExample: true).environmentObject(seeded.env)
            let image = try await snapshot(AnyView(screen), style: scheme)
            let url = base.appendingPathComponent("test-jardin-\(suffix).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("GardenViewTests: captura \(url.path)")
        }
    }

    private func snapshot(_ view: AnyView, style: UIUserInterfaceStyle) async throws -> UIImage {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = try XCTUnwrap(scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first)
        let previous = window.rootViewController
        let previousStyle = window.overrideUserInterfaceStyle
        defer {
            window.rootViewController = previous
            window.overrideUserInterfaceStyle = previousStyle
        }
        window.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = window.screen.scale
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
