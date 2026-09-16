// Rejilla (PLAN §7.5, docs/design/DESIGN_SYSTEM.md §5.3): con una AppDatabase temporal en
// disco, 3 desbloqueos dan el contador "3/348"; filtros por tamaño y estado; la observación
// sigue los cambios; buscador por número, #hex (color de Wada más cercano del motor) y texto
// sin tildes; nombres curado → propuesto → número; datos de ejemplo solo en memoria; y la
// tarjeta renderizada respeta el pocillo neutro (blanco / #303030) y NUNCA desatura los colores.
import XCTest
import SwiftUI
import UIKit
@testable import ColorsApp

final class RejillaTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("colorsapp-rejilla-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    private func makeEnvironment() throws -> AppEnvironment {
        let dictionary = try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
        let database = try AppDatabase.open(at: tempDir.appendingPathComponent("colors.sqlite"))
        return AppEnvironment(dictionary: dictionary, database: database, scanRunner: NoopScanRunner(), launches: 0)
    }

    private func loadDictionary() throws -> WadaDictionary {
        try WadaDictionary.load(from: Bundle(for: AppDatabase.self))
    }

    // MARK: Modelo

    @MainActor
    func testThreeUnlocksGiveCounterThreeOf348() async throws {
        let env = try makeEnvironment()
        let fresh = try await env.unlocks.unlock(comboIds: [1, 200, 348], source: .library, assetLocalId: "asset-1")
        XCTAssertEqual(fresh, [1, 200, 348])

        let model = RejillaModel()
        XCTAssertFalse(model.loaded)
        XCTAssertEqual(model.counterText(total: env.comboCount), "0/348")
        try await model.refresh(env.unlocks)
        XCTAssertTrue(model.loaded)
        XCTAssertEqual(model.counterText(total: env.comboCount), "3/348")
        XCTAssertEqual(RejillaModel.counterText(unlocked: 41, total: 348), "41/348")
        XCTAssertEqual(model.unlockedIds, [1, 200, 348])
        XCTAssertTrue(model.isUnlocked(200))
        XCTAssertFalse(model.isUnlocked(2))
        XCTAssertEqual(model.unlock(for: 1)?.source, .library)
        XCTAssertEqual(model.unlock(for: 1)?.assetLocalId, "asset-1")

        // Sin filtro: las 348 en orden de id.
        XCTAssertEqual(model.combos(in: env.dictionary).map(\.id), Array(1...348))
        XCTAssertEqual(model.progressText(in: env.dictionary), "3 de 348 desbloqueadas")
        // Filtro por tamaño: 120 / 120 / 108 y los desbloqueos que caen en cada uno.
        model.sizeFilter = 2
        XCTAssertEqual(model.combos(in: env.dictionary).count, 120)
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 1)
        XCTAssertEqual(model.progressText(in: env.dictionary), "1 de 120 desbloqueadas")
        model.sizeFilter = 3
        XCTAssertEqual(model.combos(in: env.dictionary).count, 120)
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 1)
        model.sizeFilter = 4
        XCTAssertEqual(model.combos(in: env.dictionary).count, 108)
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 1)
        model.sizeFilter = nil
        XCTAssertEqual(model.unlockedCount(in: env.dictionary), 3)
        // El contador global no depende del filtro.
        XCTAssertEqual(model.counterText(total: env.comboCount), "3/348")
    }

    @MainActor
    func testStatusFilterSearchAndClear() async throws {
        let env = try makeEnvironment()
        _ = try await env.unlocks.unlock(comboIds: [1, 12, 200, 348], source: .camera)
        let model = RejillaModel()
        try await model.refresh(env.unlocks)
        let d = env.dictionary
        let index = RejillaSearch.Index(dictionary: d, naming: .bundled)

        model.statusFilter = .unlocked
        XCTAssertEqual(model.results(in: d, index: index).map(\.id), [1, 12, 200, 348])
        model.statusFilter = .locked
        XCTAssertEqual(model.results(in: d, index: index).count, 344)
        XCTAssertFalse(model.results(in: d, index: index).contains { model.isUnlocked($0.id) })

        // Tamaño + estado: las desbloqueadas de 2 colores.
        model.statusFilter = .unlocked
        model.sizeFilter = 2
        let twoColors = [1, 12, 200, 348].filter { d.combo(id: $0)?.size == 2 }
        XCTAssertEqual(model.results(in: d, index: index).map(\.id), twoColors)

        // Buscador por hex dentro de los filtros: Isabella Color está en la 12 (2 colores).
        model.searchText = "#C5A56E"
        guard case .color(let match) = model.query(total: 348) else { return XCTFail("un hex es una consulta de color") }
        XCTAssertEqual(match.index, 50)
        XCTAssertEqual(model.results(in: d, index: index).map(\.id), twoColors.filter { d.combo(id: $0)!.colors.contains(50) })
        XCTAssertTrue(model.isFiltering)

        model.clearFilters()
        XCTAssertFalse(model.isFiltering)
        XCTAssertEqual(model.results(in: d, index: index).count, 348)
    }

    @MainActor
    func testObservationFollowsUnlocks() async throws {
        let env = try makeEnvironment()
        let model = RejillaModel()
        let observing = Task { await model.observe(env.unlocks) }
        defer { observing.cancel() }
        try await waitUntil("valor inicial") { model.loaded }
        XCTAssertEqual(model.counterText(total: 348), "0/348")
        _ = try await env.unlocks.unlock(comboIds: [5, 6, 7], source: .manual)
        try await waitUntil("3 desbloqueos") { model.unlockedCount == 3 }
        XCTAssertEqual(model.counterText(total: 348), "3/348")
        try await env.unlocks.unlock(comboId: 8, source: .camera)
        try await waitUntil("4 desbloqueos") { model.unlockedCount == 4 }
        XCTAssertEqual(model.unlockedIds, [5, 6, 7, 8])
        try await env.unlocks.deleteAll(source: .manual)
        try await waitUntil("solo la cámara") { model.unlockedIds == [8] }
        XCTAssertEqual(model.counterText(total: 348), "1/348")
    }

    func testCounterTextFormatting() {
        XCTAssertEqual(RejillaModel.counterText(unlocked: 0, total: 348), "0/348")
        XCTAssertEqual(RejillaModel.counterText(unlocked: 348, total: 348), "348/348")
    }

    // MARK: Buscador

    func testSearchInterpretation() throws {
        XCTAssertEqual(RejillaSearch.interpret("", count: 348), .empty)
        XCTAssertEqual(RejillaSearch.interpret("   ", count: 348), .empty)
        XCTAssertEqual(RejillaSearch.interpret("12", count: 348), .number(12))
        XCTAssertEqual(RejillaSearch.interpret("Nº 067", count: 348), .number(67))
        XCTAssertEqual(RejillaSearch.interpret("400", count: 348), .numberOutOfRange(400))
        // Seis dígitos hexadecimales son un color aunque parezcan un número.
        guard case .color(let m) = RejillaSearch.interpret("099197", count: 348) else { return XCTFail("hex") }
        XCTAssertEqual(m.index, 119)
        XCTAssertEqual(m.deltaE, 0)
        XCTAssertEqual(RejillaSearch.normalizedHex(" #c5a56e "), "#C5A56E")
        XCTAssertNil(RejillaSearch.normalizedHex("#c5a56"))
        XCTAssertEqual(RejillaSearch.interpret("  Rosa   Pálido ", count: 348), .text("rosa palido"))
        XCTAssertEqual(RejillaSearch.fold("ÁRBOL  Ñandú"), "arbol nandu")
    }

    func testSearchByNumberColorAndText() throws {
        let d = try loadDictionary()
        let naming = ComboNaming.load(bundle: Bundle(for: AppDatabase.self))
        let index = RejillaSearch.Index(dictionary: d, naming: naming)
        let all = d.combinations

        XCTAssertEqual(RejillaSearch.filter(all, query: .number(12), index: index).map(\.id), [12])
        XCTAssertEqual(RejillaSearch.filter(all, query: .numberOutOfRange(999), index: index), [])

        // Color: hex perturbado → Isabella Color (motor) → combinaciones que lo contienen.
        let match = try XCTUnwrap(ColorSearch.nearest(hex: "#c6a56e"))
        let byColor = RejillaSearch.filter(all, query: .color(match), index: index).map(\.id)
        XCTAssertEqual(byColor, d.combos(containingColor: 50).map(\.id))
        XCTAssertTrue(byColor.contains(12))

        // Texto sobre nombres de color (Ridgway), sin mayúsculas.
        let byColorName = RejillaSearch.filter(all, query: RejillaSearch.interpret("isabella color", count: 348), index: index).map(\.id)
        XCTAssertEqual(byColorName, d.combos(containingColor: 50).map(\.id))

        // Texto sobre nombres propuestos, sin tildes ni mayúsculas.
        let proposal = try XCTUnwrap(naming.proposed.sorted { $0.key < $1.key }.first { name in
            name.value.range(of: "[áéíóúñÁÉÍÓÚÑ]", options: .regularExpression) != nil
        }, "hay al menos un nombre propuesto con tilde")
        let needle = RejillaSearch.fold(proposal.value)
        XCTAssertNotEqual(needle, proposal.value.lowercased(), "la consulta pierde la tilde")
        let byName = RejillaSearch.filter(all, query: RejillaSearch.interpret(needle.uppercased(), count: 348), index: index).map(\.id)
        XCTAssertTrue(byName.contains(proposal.key), "«\(needle)» encuentra la Nº \(proposal.key) («\(proposal.value)»)")
        XCTAssertEqual(RejillaSearch.filter(all, query: .text("zzzz-no-existe"), index: index), [])
    }

    // MARK: Nombres

    func testNamingCuratedThenProposedThenNumber() throws {
        let d = try loadDictionary()
        let naming = ComboNaming.load(bundle: Bundle(for: AppDatabase.self))
        XCTAssertEqual(naming.proposed.count, 348, "names.suggested.json va en el bundle con las 348 propuestas")
        XCTAssertTrue(naming.proposed.values.allSatisfy { !$0.isEmpty && $0.count <= 25 })

        // names.es.json está todo pendiente: la 1 lleva su nombre propuesto.
        XCTAssertNil(d.curatedName(id: 1))
        let proposed = naming.name(for: 1, in: d)
        XCTAssertEqual(proposed.kind, .proposed)
        XCTAssertEqual(proposed.text, naming.proposed[1])
        XCTAssertEqual(proposed.kindLabel, "Nombre propuesto")

        // Sin propuestas: número.
        XCTAssertEqual(ComboNaming.empty.name(for: 67, in: d), ComboName(text: "Nº 067", kind: .number))

        // Con un nombre aceptado, gana el curado.
        let curatedDictionary = WadaDictionary(schema: d.schema, source: d.source, dictVersion: d.dictVersion, status: d.status,
                                               colors: d.colors, combinations: d.combinations,
                                               names: [WadaName(id: 1, lang: "es", name: "Tejas y mar", notes: "", status: "accepted")])
        XCTAssertEqual(naming.name(for: 1, in: curatedDictionary), ComboName(text: "Tejas y mar", kind: .curated))

        // JSON inválido o vacío: sin propuestas, sin fallo.
        XCTAssertThrowsError(try ComboNaming.decode(Data("{}".utf8)))
        let decoded = try ComboNaming.decode(Data(#"{"suggestions":[{"id":3,"name_es":"  Pan  "},{"id":4,"name_es":" "}]}"#.utf8))
        XCTAssertEqual(decoded.proposed, [3: "Pan"])
    }

    // MARK: Al azar, fechas y atajos

    func testRandomNeverRepeatsCurrent() {
        var g = SeededGenerator(seed: 7)
        var current = 1
        for _ in 0..<500 {
            let next = RejillaRandom.next(after: current, total: 348, using: &g)
            XCTAssertNotEqual(next, current)
            XCTAssertTrue((1...348).contains(next))
            current = next
        }
        XCTAssertEqual(RejillaRandom.next(after: 1, total: 1), 1)
    }

    func testShortDatesInSpanish() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 45)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let lastYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 3)))
        XCTAssertEqual(RejillaDateText.short(date, now: now, calendar: calendar), "14 sept")
        XCTAssertTrue(RejillaDateText.short(lastYear, now: now, calendar: calendar).contains("2025"))
        XCTAssertTrue(RejillaDateText.long(date, calendar: calendar).contains("14 sept 2026"))
    }

    func testLaunchOptions() {
        XCTAssertEqual(RejillaLaunchOptions.parse([]), .empty)
        let demo = RejillaLaunchOptions.parse(["-uiScreen", "rejilla-demo", "-uiRejillaSearch", "#C5A56E", "-uiRejillaSize", "3",
                                               "-uiRejillaStatus", "locked", "-uiRejillaScrollTo", "40"])
        XCTAssertTrue(demo.demo)
        XCTAssertEqual(demo.search, "#C5A56E")
        XCTAssertEqual(demo.size, 3)
        XCTAssertEqual(demo.status, .locked)
        XCTAssertEqual(demo.scrollTo, 40)
        XCTAssertTrue(RejillaLaunchOptions.parse(["-uiScreen", "rejilla", "-uiRejillaDemo"]).demo)
        XCTAssertEqual(RejillaLaunchOptions.parse(["-uiScreen", "explorar-67"]).detailId, 67)
        XCTAssertEqual(RejillaLaunchOptions.parse(["-uiRejillaDetail", "12", "-uiRejillaSize", "9"]).detailId, 12)
        XCTAssertNil(RejillaLaunchOptions.parse(["-uiRejillaSize", "9"]).size)
        XCTAssertFalse(RejillaLaunchOptions.parse(["-uiScreen", "rejilla"]).demo)
    }

    @MainActor
    func testRequestsFromOtherTabsAreConsumedOnce() {
        let requests = RejillaRequests()
        XCTAssertNil(requests.consume())
        requests.open(size: 3)
        let first = requests.consume()
        XCTAssertEqual(first?.size, 3)
        XCTAssertNil(first?.status)
        XCTAssertNil(requests.pending)
        XCTAssertNil(requests.consume())
        // La última petición gana y cada una es distinta aunque repita filtros.
        requests.open(status: .locked, comboId: 12)
        let a = requests.pending
        requests.open(status: .locked, comboId: 12)
        XCTAssertNotEqual(a, requests.pending)
        requests.open(search: "#C5A56E")
        XCTAssertEqual(requests.consume()?.search, "#C5A56E")
    }

    #if DEBUG
    @MainActor
    func testDemoDataLivesInMemoryAndIsMarked() async throws {
        let real = try makeEnvironment()
        let demo = try RejillaDemo.makeEnvironment(dictionary: real.dictionary)
        try await RejillaDemo.seed(demo)
        let unlocks = try await demo.unlocks.all()
        XCTAssertEqual(unlocks.count, RejillaDemo.unlocks.count)
        XCTAssertTrue(unlocks.allSatisfy { $0.assetLocalId == RejillaDemo.marker })
        let seen12 = try await demo.scans.scans(withTop1: 12)
        XCTAssertEqual(seen12.count, 2)
        XCTAssertTrue(seen12.allSatisfy { $0.assetLocalId == RejillaDemo.marker })
        let realCount = try await real.unlocks.count()
        XCTAssertEqual(realCount, 0, "la base de datos real no recibe datos de ejemplo")
        let garden = RejillaDemo.makeGarden()
        XCTAssertNil(garden.url, "Jardín de ejemplo solo en memoria")
        XCTAssertEqual(garden.savedComboIds, Set(RejillaDemo.savedComboIds))
    }
    #endif

    // MARK: Render

    @MainActor
    func testGridRendersWithUnlocks() async throws {
        let env = try makeEnvironment()
        _ = try await env.unlocks.unlock(comboIds: [1, 200, 348], source: .library)
        let model = RejillaModel()
        try await model.refresh(env.unlocks)
        for scheme in [ColorScheme.light, .dark] {
            let content = RejillaContentView(model: model, dictionary: env.dictionary, randomId: 255, savedComboIds: [1],
                                             onToggleSave: { _ in })
                .frame(width: 390, height: 844)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "la rejilla no se renderiza")
            XCTAssertEqual(image.width, 780)
            XCTAssertEqual(image.height, 1688)
        }
        // Búsqueda sin resultados y por color también se construyen.
        model.searchText = "zzzz"
        XCTAssertNotNil(ImageRenderer(content: RejillaContentView(model: model, dictionary: env.dictionary).frame(width: 390, height: 600)).cgImage)
        model.searchText = "#c5a56e"
        XCTAssertNotNil(ImageRenderer(content: RejillaContentView(model: model, dictionary: env.dictionary).frame(width: 390, height: 600)).cgImage)

        // Casilla compacta (resumen del carrete), desbloqueada y bloqueada.
        let combo = try XCTUnwrap(env.dictionary.combo(id: 1))
        let tile = ComboTile(combo: combo, colors: env.dictionary.colors(of: combo), unlocked: true)
            .frame(width: 60, height: 60)
        XCTAssertNotNil(ImageRenderer(content: tile).cgImage)
        let locked = ComboTile(combo: combo, colors: env.dictionary.colors(of: combo), unlocked: false)
            .frame(width: 60, height: 60)
        XCTAssertNotNil(ImageRenderer(content: locked).cgImage)
        XCTAssertNotNil(model.unlock(for: 1))
        // El detalle es ComboDetailView (con .task): se aloja en un UIHostingController;
        // ImageRenderer de una vista con .task dentro de NavigationStack aborta al liberarse (iOS 27).
        let host = UIHostingController(rootView: RejillaComboDetailView(combo: combo, garden: GardenStore(url: nil), onClose: {})
            .environmentObject(env))
        XCTAssertGreaterThan(host.sizeThatFits(in: CGSize(width: 390, height: 2000)).height, 100,
                             "el detalle de la rejilla se construye y ocupa espacio")
        XCTAssertEqual(RejillaComboDetailView.sourceLabel(.library), "carrete")
        let colorSearch = UIHostingController(rootView: ColorSearchView(onShowInGrid: { _ in }, onClose: {}).environmentObject(env))
        XCTAssertGreaterThan(colorSearch.sizeThatFits(in: CGSize(width: 390, height: 2000)).height, 100)
    }

    /// Pocillo de la tarjeta: blanco exacto en claro y #303030 en oscuro; las franjas conservan
    /// el sRGB exacto de Wada también bloqueadas, y solo el marco de la bloqueada pasa a gris.
    @MainActor
    func testGridCardWellIsNeutralAndLockedKeepsExactColors() throws {
        let d = try loadDictionary()
        let colors = PaletteColor.combo(12, in: d) // Isabella Color #c5a56e, Green Blue #099197
        XCTAssertEqual(colors.map(\.hex), ["#C5A56E", "#099197"])
        let name = ComboName(text: "Nombre de prueba", kind: .proposed)
        for scheme in [ColorScheme.light, .dark] {
            for state in [ComboGridCard.State.unlocked(since: "14 sept"), .locked] {
                let card = ComboGridCard(comboId: 12, name: name, colors: colors, state: state, onOpen: {}, onToggleSave: {})
                    .frame(width: 180)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: card)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                let px = try rgbaPixels(image)
                let label = "\(scheme) \(state)"
                // Relleno del pocillo (6 pt): a 3 pt del borde superior, en el centro y a los lados.
                let well: UInt8 = scheme == .light ? 255 : 48
                for (x, y) in [(90, 3), (30, 3), (150, 3), (90, 109)] {
                    let p = px.pixel(x * 2, y * 2)
                    XCTAssertEqual([p.r, p.g, p.b], [well, well, well], "\(label): pocillo en (\(x),\(y)) = \(p)")
                }
                // Franjas: el color exacto de Wada, sin desaturar.
                let first = px.pixel(40 * 2, 56 * 2)
                XCTAssertEqual([first.r, first.g, first.b], [197, 165, 110], "\(label): Isabella Color = \(first)")
                let second = px.pixel(130 * 2, 56 * 2)
                XCTAssertEqual([second.r, second.g, second.b], [9, 145, 151], "\(label): Green Blue = \(second)")
                // Marco: a 3 pt del borde derecho, a media altura del cuerpo. Desde el ajuste de
                // fidelidad, la BLOQUEADA usa la misma tarjeta clara y luminosa que la desbloqueada
                // (la placa gris se reserva para el modo de alto contraste, `dimsLocked`).
                let frame = px.pixel(177 * 2, (112 + 20) * 2)
                if scheme == .light {
                    XCTAssertEqual([frame.r, frame.g, frame.b], [255, 255, 255], "\(label): tarjeta blanca = \(frame)")
                } else {
                    XCTAssertEqual([frame.r, frame.g, frame.b], [0x1C, 0x19, 0x13], "\(label): tarjeta cálida = \(frame)")
                }
            }
        }
    }

    // MARK: Utilidades

    @MainActor
    private func waitUntil(_ what: String, timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timeout esperando: \(what)")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let data: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let i = (min(y, height - 1) * width + min(x, width - 1)) * 4
            return (data[i], data[i + 1], data[i + 2])
        }
    }

    private func rgbaPixels(_ image: CGImage) throws -> Pixels {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(ok)
        return Pixels(width: w, height: h, data: data)
    }
}

/// Generador determinista (SplitMix64) para probar la tarjeta «Al azar».
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
