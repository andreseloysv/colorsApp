// Pestaña Feed (docs/design/DESIGN_SYSTEM.md §5.1): combinación del día, filtros, textos de
// la publicación a partir de un scan guardado, nombres, almacén de fotos, voto desde el
// Feed (feedback + copia del diagnóstico), «Abrir en Extraer» sin scans duplicados,
// borrado, tarjeta compartible 4:5 y 9:16, navegación raíz y atajos de depuración.
import XCTest
import SwiftUI
import UIKit
import ImageIO
import ColorEngine
import SubjectKit
@testable import ColorsApp

@MainActor
final class FeedTests: XCTestCase {
    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment.forTesting(bundle: Bundle(for: AppDatabase.self))
    }

    private func temporaryDirectory(_ name: String = "feed") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("colorsapp-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func timing() -> TimingLog {
        TimingLog(url: temporaryDirectory("timing").appendingPathComponent("t.txt"))
    }

    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    /// Scan real de la escena sintética de una persona (cadena de máscaras del motor, sin Vision).
    private func personScan(env: AppEnvironment, source: ScanSource = .camera, store: ScanPhotoStore? = nil) async throws -> ScanOutcome {
        let scene = SyntheticPersonScene.make()
        let image = try XCTUnwrap(scene.image)
        return try await ScanAnalyzer.run(image: image, source: source, subject: .default, people: [scene.person], env: env,
                                          timing: timing(), now: Date(timeIntervalSince1970: 1_750_000_001), photoStore: store)
    }

    private func feedItems(env: AppEnvironment) async throws -> [FeedItem] {
        try await env.scans.recent().map { FeedItem(scan: $0, dictionary: env.dictionary) }
    }

    // MARK: Combinación del día

    func testDayPickUsesLocalDaysSince1970() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = madrid
        // 2026-09-15 en Madrid: 20711 días desde 1970 → (20711 × 7919) mod 348 + 1 = 98.
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        XCTAssertEqual(DayPick.localDaysSince1970(noon, calendar: calendar), 20711)
        XCTAssertEqual(DayPick.comboId(for: noon, calendar: calendar), 98)
        // 23:30 del 15 en Madrid (21:30 UTC) sigue siendo el 15; 00:30 del 16 (22:30 UTC del 15) ya es el 16.
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 30))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 0, minute: 30))!
        XCTAssertEqual(DayPick.comboId(for: lateNight, calendar: calendar), 98)
        XCTAssertEqual(DayPick.comboId(for: afterMidnight, calendar: calendar), 13)
        for offset in 0..<400 {
            let id = DayPick.comboId(for: noon.addingTimeInterval(Double(offset) * 86_400), calendar: calendar)
            XCTAssertTrue((1...348).contains(id))
        }
    }

    func testAnotherComboIsDifferentAndCoversTheRange() {
        var generator = SeededGenerator(seed: 7)
        var seen = Set<Int>()
        for i in 0..<20_000 {
            let current = i % 348 + 1
            let next = DayPick.another(than: current, using: &generator)
            XCTAssertNotEqual(next, current)
            XCTAssertTrue((1...348).contains(next))
            seen.insert(next)
        }
        XCTAssertEqual(seen.count, 348, "todas las combinaciones pueden salir")
        XCTAssertEqual(DayPick.another(than: 1, count: 1), 1)
    }

    // MARK: Filtros

    func testFilters() {
        XCTAssertEqual(FeedFilter.allCases.map(\.title), ["Todo", "2 colores", "3 colores", "4 colores", "Guardadas", "Por votar"])
        XCTAssertTrue(FeedFilter.all.includes(top1Size: nil, verdict: .no, isSaved: false))
        XCTAssertTrue(FeedFilter.three.includes(top1Size: 3, verdict: nil, isSaved: false))
        XCTAssertFalse(FeedFilter.three.includes(top1Size: 2, verdict: nil, isSaved: true))
        XCTAssertFalse(FeedFilter.two.includes(top1Size: nil, verdict: nil, isSaved: false))
        XCTAssertTrue(FeedFilter.saved.includes(top1Size: 4, verdict: .yes, isSaved: true))
        XCTAssertFalse(FeedFilter.saved.includes(top1Size: 4, verdict: .yes, isSaved: false))
        XCTAssertTrue(FeedFilter.unvoted.includes(top1Size: 2, verdict: nil, isSaved: false))
        XCTAssertFalse(FeedFilter.unvoted.includes(top1Size: 2, verdict: .yes, isSaved: false))
        XCTAssertEqual(FeedFilter.allCases.compactMap(\.systemImage), ["sun.max.fill"], "solo «Todo» lleva icono; sin puntos de color")
    }

    // MARK: Nombres

    func testComboNamePriority() throws {
        let env = try makeEnvironment()
        let d = env.dictionary
        let colors = d.colors(ofComboId: 69).map(\.name)
        XCTAssertEqual(FeedComboName.name(69, in: d, naming: .none), colors.prefix(2).joined(separator: " · "))
        XCTAssertEqual(FeedComboName.name(69, in: d, naming: ComboNaming(proposed: [69: "Gris de tranvía"])), "Gris de tranvía")
        XCTAssertEqual(FeedComboName.name(999, in: d, naming: .none), "Nº 999")
    }

    // MARK: Publicación

    func testPostTextsFromAPersonScan() async throws {
        let env = try makeEnvironment()
        let outcome = try await personScan(env: env)
        let scan = outcome.scan
        XCTAssertEqual(scan.subjectMode, SubjectMode.largestPerson.rawValue)

        // 2025-06-15 15:06:41 UTC = 17:06 en Madrid; el año solo aparece si no es el actual.
        let date = FeedPostText.date(scan.scannedAt, timeZone: madrid, now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertTrue(date.contains("2025") && date.contains("17:06") && date.lowercased().contains("jun"), date)
        let sameYear = FeedPostText.date(scan.scannedAt, timeZone: madrid, now: scan.scannedAt)
        XCTAssertTrue(sameYear.contains("15") && sameYear.contains("17:06") && !sameYear.contains("2025"), sameYear)
        XCTAssertEqual(FeedPostText.person(scan), "1 persona")
        XCTAssertEqual(FeedPostText.metadata(scan, timeZone: madrid, now: scan.scannedAt), "\(sameYear) · 1 persona")
        XCTAssertEqual(FeedPostText.metadata(scan, timeZone: madrid, isExample: true, now: scan.scannedAt),
                       "Ejemplo · \(sameYear) · 1 persona")
        let notice = try XCTUnwrap(FeedPostText.cropNotice(scan))
        XCTAssertTrue(notice.text.hasPrefix("Solo ropa"), notice.text)
        XCTAssertEqual(FeedPostText.paletteTitle(scan), "Paleta de la ropa")
        XCTAssertEqual(FeedPostText.source(.camera), .camera)
        XCTAssertEqual(FeedPostText.source(.library), .library)
        XCTAssertEqual(FeedPostText.source(.picker), .picked)

        var off = scan
        off.subjectMode = SubjectMode.off.rawValue
        off.maskSteps = JSONCoding.encode([MaskFallback.none.rawValue])
        off.maskCoverage = 0
        XCTAssertEqual(FeedPostText.cropNotice(off)?.text, "Foto completa")
        XCTAssertEqual(FeedPostText.cropNotice(off)?.isFallback, false)
        XCTAssertEqual(FeedPostText.paletteTitle(off), "Paleta de la foto")
        XCTAssertEqual(FeedPostText.person(off), "Foto completa")

        var group = scan
        group.subjectMode = SubjectMode.allPeople.rawValue
        group.peopleCount = 3
        group.maskSteps = JSONCoding.encode([MaskFallback.poseRegions.rawValue])
        XCTAssertEqual(FeedPostText.person(group), "Todas las personas (3)")
        XCTAssertEqual(FeedPostText.cropNotice(group)?.text, "Todas las personas (3) · solo ropa")

        var second = scan
        second.subjectMode = SubjectMode.selectedPerson.rawValue
        second.peopleCount = 3
        second.personIndex = 1
        XCTAssertEqual(FeedPostText.person(second), "Persona 2 de 3")
        second.personIndex = 0
        XCTAssertEqual(FeedPostText.person(second), "Persona principal de 3")

        var noVision = scan
        noVision.maskSteps = JSONCoding.encode([MaskFallback.visionUnavailable.rawValue])
        noVision.maskCoverage = 0
        XCTAssertEqual(FeedPostText.cropNotice(noVision)?.text, "Foto completa")
        XCTAssertEqual(FeedPostText.cropNotice(noVision)?.isFallback, true)

        var legacy = scan
        legacy.subjectMode = nil
        XCTAssertNil(FeedPostText.cropNotice(legacy))
        XCTAssertNil(FeedPostText.person(legacy))

        XCTAssertEqual(FeedPostText.copiedToast(count: 1, single: "#222524"), "Copiado #222524")
        XCTAssertEqual(FeedPostText.copiedToast(count: 4), "Copiados 4 hex")
        XCTAssertEqual(FeedPostText.dayStatus(size: 4, unlocked: false), "4 colores · Bloqueada")
        XCTAssertEqual(FeedPostText.dayStatus(size: 2, unlocked: true), "2 colores · En tu rejilla")
    }

    func testFeedItemUsesEnginePaletteAndMatch() async throws {
        let env = try makeEnvironment()
        let outcome = try await personScan(env: env)
        var scan = outcome.scan
        let item = FeedItem(scan: scan, dictionary: env.dictionary, timeZone: madrid)
        XCTAssertEqual(item.palette.count, scan.palette.count)
        XCTAssertEqual(item.palette.map(\.hex), scan.palette.map { $0.hex.uppercased() })
        XCTAssertTrue(item.palette.allSatisfy { $0.name != nil && $0.deltaE != nil }, "nombre de Wada más cercano del motor")
        let match = try XCTUnwrap(item.match)
        XCTAssertEqual(match.comboId, scan.top1)
        XCTAssertEqual(match.colors.count, env.dictionary.combo(id: match.comboId)?.size)
        XCTAssertEqual(item.top1Size, match.colors.count)
        XCTAssertEqual(item.comboHexList, match.colors.map(\.hex).joined(separator: " "))
        XCTAssertNil(match.ambiguityText)

        scan.ambiguous = true
        scan.top1 = 337
        scan.top2 = 27
        XCTAssertEqual(FeedComboName.match(for: scan, in: env.dictionary)?.ambiguityText, "Entre Nº 337 y Nº 027")
        scan.top1 = nil
        XCTAssertNil(FeedComboName.match(for: scan, in: env.dictionary))
    }

    // MARK: Fotos

    func testScanPhotoStoreWritesSmallJPEGWithoutMetadata() throws {
        let store = ScanPhotoStore(directory: temporaryDirectory("photos"))
        defer { store.removeAll() }
        let big = try XCTUnwrap(SyntheticImage.blocks(colors: [.init(r: 197, g: 165, b: 110), .init(r: 9, g: 145, b: 151)], size: 2048))
        try store.save(big, scanId: "abc")
        XCTAssertTrue(store.exists(scanId: "abc"))
        let back = try XCTUnwrap(store.image(scanId: "abc"))
        XCTAssertEqual(max(back.width, back.height), ScanPhotoStore.maxSide)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(store.url(scanId: "abc") as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        XCTAssertNil(props[kCGImagePropertyTIFFDictionary])
        store.remove(scanId: "abc")
        XCTAssertFalse(store.exists(scanId: "abc"))
        XCTAssertNil(store.image(scanId: "abc"))
    }

    func testRunStoresPhotoForCameraButNotForLibrary() async throws {
        let env = try makeEnvironment()
        let store = ScanPhotoStore(directory: temporaryDirectory("photos"))
        defer { store.removeAll() }
        let camera = try await personScan(env: env, source: .camera, store: store)
        XCTAssertTrue(store.exists(scanId: camera.scan.id), "cámara y foto elegida: copia local para el Feed")
        let library = try await personScan(env: env, source: .library, store: store)
        XCTAssertFalse(store.exists(scanId: library.scan.id), "carrete: se lee de PhotoKit por assetLocalId")
        let loaded = await ScanPhotoLoader.image(for: camera.scan, store: store,
                                                  feedbackImages: FeedbackImageStore(directory: temporaryDirectory("fb")))
        XCTAssertEqual(loaded?.width, camera.image.width)
        let missing = await ScanPhotoLoader.image(for: library.scan, store: store,
                                                   feedbackImages: FeedbackImageStore(directory: temporaryDirectory("fb")))
        XCTAssertNil(missing, "sin foto guardada, sin asset y sin copia de diagnóstico")
    }

    // MARK: Acciones

    func testVoteFromFeedRecordsVerdictAndDiagnosticsCopy() async throws {
        let env = try makeEnvironment()
        let photos = ScanPhotoStore(directory: temporaryDirectory("photos"))
        let images = FeedbackImageStore(directory: temporaryDirectory("fb"))
        defer { photos.removeAll(); images.removeAll() }
        let outcome = try await personScan(env: env, store: photos)
        try await FeedServices.vote(.yes, scan: outcome.scan, env: env, photoStore: photos, imageStore: images)
        let latest = try await env.feedback.latest(forScan: outcome.scan.id)
        XCTAssertEqual(latest?.verdict, .yes)
        // La copia de 256 px se escribe en segundo plano.
        var png: Data?
        for _ in 0..<100 where png == nil {
            png = images.data(scanId: outcome.scan.id)
            if png == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        let data = try XCTUnwrap(png, "copia PNG del diagnóstico")
        let cg = try ImageLoading.cgImage(from: data)
        XCTAssertEqual(max(cg.width, cg.height), DiagnosticsSubject.exportSide)
    }

    func testReopenReanalyzesWithoutInsertingAScan() async throws {
        let env = try makeEnvironment()
        let outcome = try await personScan(env: env)
        let before = try await env.scans.count()
        let reopened = try await FeedServices.reopen(scan: outcome.scan, image: outcome.image, fallback: .default)
        let after = try await env.scans.count()
        XCTAssertEqual(before, after, "«Abrir en Extraer» nunca crea otro scan")
        XCTAssertEqual(reopened.outcome.scan, outcome.scan)
        XCTAssertEqual(reopened.outcome.subjectOptions.mode, .largestPerson)
        XCTAssertEqual(reopened.outcome.subjectOptions.region, .clothing)
        XCTAssertNotNil(reopened.outcome.debug, "capas para el inspector")
        // En el simulador Vision no detecta a la persona sintética: el top-1 puede cambiar y se avisa.
        XCTAssertEqual(reopened.recalculated, reopened.outcome.result.hits.first?.comboId != outcome.scan.top1)

        let selected = FeedServices.subjectOptions(for: {
            var s = outcome.scan
            s.subjectMode = SubjectMode.selectedPerson.rawValue
            s.personIndex = 2
            s.regionMode = RegionMode.wholePerson.rawValue
            s.adaptiveSkin = false
            return s
        }(), fallback: .default)
        XCTAssertEqual(selected.mode, .selectedPerson)
        XCTAssertEqual(selected.selectedIndex, 2)
        XCTAssertEqual(selected.region, .wholePerson)
        XCTAssertFalse(selected.adaptiveSkin)
    }

    func testDeleteRemovesScanPhotoAndSavedItem() async throws {
        let env = try makeEnvironment()
        let photos = ScanPhotoStore(directory: temporaryDirectory("photos"))
        defer { photos.removeAll() }
        let garden = GardenStore(url: nil)
        let outcome = try await personScan(env: env, store: photos)
        XCTAssertTrue(garden.toggle(scanId: outcome.scan.id))
        try await FeedServices.delete(scan: outcome.scan, env: env, garden: garden, photoStore: photos)
        let recent = try await env.scans.recent()
        XCTAssertFalse(recent.contains { $0.id == outcome.scan.id })
        XCTAssertFalse(photos.exists(scanId: outcome.scan.id))
        XCTAssertFalse(garden.isSaved(scanId: outcome.scan.id))
    }

    // MARK: Tarjeta compartible

    func testShareCardFromScanRendersPostAndStory() async throws {
        let env = try makeEnvironment()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let outcome = try await ScanAnalyzer.run(image: image, source: .camera, subject: SubjectOptions(mode: .off), env: env,
                                                  timing: timing(), photoStore: nil)
        for (format, height) in [(ShareCardFormat.post, 1350), (.story, 1920)] {
            let card = ShareCardRenderer.card(for: outcome.scan, photo: image, dictionary: env.dictionary, format: format)
            XCTAssertEqual(card.number, "Nº 012")
            XCTAssertEqual(card.subtitle, "Nº 012 · 2 colores")
            let rendered = try XCTUnwrap(ShareCardRenderer.render(card))
            let cg = try XCTUnwrap(rendered.cgImage)
            XCTAssertEqual(cg.width, 1080)
            XCTAssertEqual(cg.height, height)
            let raster = try EngineBridge.rasterize(cg, maxSide: 4096)
            var hexes = Set<String>()
            for i in stride(from: 0, to: raster.pixels.count, by: 4) {
                hexes.insert(String(format: "#%02x%02x%02x", raster.pixels[i], raster.pixels[i + 1], raster.pixels[i + 2]))
            }
            XCTAssertTrue(hexes.contains("#c5a56e"), "\(format): Isabella Color")
            XCTAssertTrue(hexes.contains("#099197"), "\(format): Green Blue")
            XCTAssertTrue(hexes.contains("#ffffff"), "\(format): pocillos blancos")
            XCTAssertTrue(hexes.contains("#fcf9f1"), "\(format): marco pergamino (siempre claro)")
        }
        // Sin foto también se dibuja (la paleta ocupa el sitio de la foto).
        let noPhoto = ShareCardRenderer.card(for: outcome.scan, photo: nil, dictionary: env.dictionary)
        XCTAssertNotNil(ShareCardRenderer.render(noPhoto))
    }

    func testShareCardIsLightInDarkMode() async throws {
        let env = try makeEnvironment()
        let image = try XCTUnwrap(SyntheticImage.blocks(comboId: 12, dictionary: env.dictionary))
        let outcome = try await ScanAnalyzer.run(image: image, source: .camera, subject: SubjectOptions(mode: .off), env: env,
                                                  timing: timing(), photoStore: nil)
        let card = ShareCardRenderer.card(for: outcome.scan, photo: image, dictionary: env.dictionary)
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(card.format.size)
        let cg = try XCTUnwrap(renderer.cgImage)
        let raster = try EngineBridge.rasterize(cg, maxSide: 4096)
        // Esquina superior izquierda (marco): pergamino claro, no el fondo oscuro.
        let i = (4 * raster.width + 4) * 4
        XCTAssertGreaterThan(Int(raster.pixels[i]), 230)
        XCTAssertGreaterThan(Int(raster.pixels[i + 1]), 230)
    }

    /// Muestras de la tarjeta con una foto real (harness/people, CC0) para docs/design/screens:
    /// solo si se pasa `TEST_RUNNER_COLORSAPP_FEED_CARDS_DIR=<dir>` a xcodebuild.
    func testWriteShareCardSamplesWhenRequested() async throws {
        guard let dir = ProcessInfo.processInfo.environment["COLORSAPP_FEED_CARDS_DIR"], !dir.isEmpty else {
            throw XCTSkip("Sin COLORSAPP_FEED_CARDS_DIR: no se escriben muestras")
        }
        let env = try makeEnvironment()
        let url = try XCTUnwrap(Bundle(for: FeedTests.self).url(forResource: "03_couple_denim_street", withExtension: "png"))
        let photo = try ImageLoading.cgImage(from: url)
        let outcome = try await ScanAnalyzer.run(image: photo, source: .picker, subject: SubjectOptions(mode: .off), env: env,
                                                  timing: timing(), photoStore: nil)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        for (format, name) in [(ShareCardFormat.post, "feed-card-4x5.png"), (.story, "feed-card-9x16.png")] {
            let card = ShareCardRenderer.card(for: outcome.scan, photo: photo, dictionary: env.dictionary, format: format)
            let data = try XCTUnwrap(ShareCardRenderer.render(card)?.pngData())
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    // MARK: Vistas y navegación

    func testFeedAndRootBuild() async throws {
        let env = try makeEnvironment()
        let photos = ScanPhotoStore(directory: temporaryDirectory("photos"))
        defer { photos.removeAll() }
        _ = try await personScan(env: env, store: photos)
        let feed = UIHostingController(rootView: FeedView(garden: GardenStore(url: nil), photoStore: photos).environmentObject(env))
        XCTAssertGreaterThan(feed.sizeThatFits(in: CGSize(width: 390, height: 2000)).height, 100)
        let root = UIHostingController(rootView: RootTabContainer(initialTab: .feed).environmentObject(env))
        XCTAssertGreaterThan(root.sizeThatFits(in: CGSize(width: 390, height: 844)).height, 100)
        // Tamaños de accesibilidad: variantes verticales sin truncar (§5.1).
        let items = try await feedItems(env: env)
        let item = try XCTUnwrap(items.first)
        let axPost = UIHostingController(rootView: FeedAccessiblePostCard(content: FeedPostContent(
            source: .camera, metadata: item.metadata, photo: nil, cropNotice: item.notice, paletteTitle: item.paletteTitle,
            palette: item.palette, match: item.match, verdict: .yes, isSaved: true))
            .environment(\.dynamicTypeSize, .accessibility5))
        let regular = UIHostingController(rootView: FeedPostCard(content: FeedPostContent(
            source: .camera, metadata: item.metadata, photo: nil, cropNotice: item.notice, paletteTitle: item.paletteTitle,
            palette: item.palette, match: item.match, verdict: .yes, isSaved: true)))
        XCTAssertGreaterThan(axPost.sizeThatFits(in: CGSize(width: 390, height: 20_000)).height,
                             regular.sizeThatFits(in: CGSize(width: 390, height: 20_000)).height)
        let axDay = UIHostingController(rootView: FeedAccessibleDayCard(eyebrow: "Combinación del día", numberLabel: "Nº 098",
                                                                        name: "Caoba y añil", colors: PaletteColor.combo(98, in: env.dictionary),
                                                                        status: "2 colores · Bloqueada", onShuffle: {})
            .environment(\.dynamicTypeSize, .accessibility5))
        XCTAssertGreaterThan(axDay.sizeThatFits(in: CGSize(width: 390, height: 4000)).height, 200)
        let empty = UIHostingController(rootView: FeedEmptyState(onAnalyze: {}, onScanLibrary: {}))
        XCTAssertGreaterThan(empty.sizeThatFits(in: CGSize(width: 390, height: 2000)).height, 200)
        let banner = UIHostingController(rootView: FeedScanBanner(progress: ScanProgress(phase: .analyzing, processed: 3, total: 10)))
        XCTAssertGreaterThan(banner.sizeThatFits(in: CGSize(width: 390, height: 400)).height, 40)
    }

    func testTabsAndScanBadge() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Feed", "Extraer", "Rejilla", "Jardín"])
        XCTAssertEqual(AppTab.allCases.map(\.systemImage), ["sun.max", "drop.halffull", "square.grid.2x2", "leaf"])
        XCTAssertNil(RootTabContainer.scanBadge(.idle))
        XCTAssertEqual(RootTabContainer.scanBadge(ScanProgress(phase: .analyzing, processed: 37, total: 200)), "37")
        XCTAssertNil(RootTabContainer.scanBadge(ScanProgress(phase: .finished, processed: 200, total: 200)))
        XCTAssertTrue(FeedScanBanner.isVisible(ScanProgress(phase: .fetching)))
        XCTAssertFalse(FeedScanBanner.isVisible(.idle))
        XCTAssertEqual(FeedScanBanner.text(ScanProgress(phase: .analyzing, processed: 3, total: 10)), "Analizando 3/10 fotos del carrete")
    }

    func testDebugLaunchScreensAndInitialTab() {
        func screen(_ v: String) -> DebugLaunch.Screen? { DebugLaunch.screen(from: ["ColorsApp", "-uiScreen", v]) }
        XCTAssertEqual(screen("feed"), .feed)
        XCTAssertEqual(screen("feed-demo"), .feedDemo)
        XCTAssertEqual(screen("feed-empty"), .feedEmpty)
        XCTAssertEqual(screen("extraer"), .extraer)
        XCTAssertEqual(screen("rejilla"), .rejilla)
        XCTAssertEqual(screen("jardin"), .jardin)
        func tab(_ args: [String]) -> AppTab { DebugLaunch.initialTab(from: ["ColorsApp"] + args) }
        XCTAssertEqual(tab([]), .feed)
        XCTAssertEqual(tab(["-uiScreen", "feed-demo"]), .feed)
        XCTAssertEqual(tab(["-uiScreen", "result-demo"]), .extraer)
        XCTAssertEqual(tab(["-uiScreen", "layers-people", "-uiLayer", "6"]), .extraer)
        XCTAssertEqual(tab(["-uiScreen", "explorar-12"]), .rejilla)
        XCTAssertEqual(tab(["-uiScreen", "rejilla-demo"]), .rejilla)
        XCTAssertEqual(tab(["-uiScreen", "ajustes"]), .jardin)
        XCTAssertEqual(tab(["-uiScreen", "jardin-demo"]), .jardin)
        XCTAssertEqual(tab(["-uiScreen", "otra"]), .feed)
        XCTAssertEqual(tab(["-uiScreen", "design-gallery"]), .feed)
    }
}

/// Generador determinista para los tests (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
