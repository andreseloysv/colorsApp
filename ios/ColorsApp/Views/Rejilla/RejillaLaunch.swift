// Atajos de depuración de la Rejilla (solo DEBUG) y datos de EJEMPLO.
//   -uiScreen rejilla                    pestaña Rejilla con la base de datos real (DebugLaunch)
//   -uiScreen rejilla-demo               Rejilla con desbloqueos, análisis y guardadas de ejemplo en una
//                                        base de datos EN MEMORIA (la real no se toca), con la insignia
//                                        «Datos de ejemplo»; equivalente: -uiScreen rejilla -uiRejillaDemo
//   -uiScreen explorar-<id>              abre el detalle de esa combinación (alias histórico)
// Estados para capturas (se combinan con los anteriores):
//   -uiRejillaSearch <texto>   buscador ya escrito («#C5A56E», «12», «rosa»)
//   -uiRejillaSize 2|3|4       chip de tamaño      -uiRejillaStatus unlocked|locked   chip de estado
//   -uiRejillaDetail <id>      hoja de detalle (con -uiRejillaDetailLarge, desplegada)
//   -uiRejillaColorSearch      hoja «Buscar por color»
//   -uiRejillaScrollTo <id>    desplaza la cuadrícula hasta esa tarjeta
// Movimiento y luz (FIDELITY.md §8.3):
//   -uiRejillaMotionTime <s>   congela todos los efectos de la pestaña en ese instante (capturas A/B)
//   -uiRejillaReduceMotion 1   fuerza «Reducir movimiento» en la pestaña (reposo quieto)
//   -uiRejillaAutoShuffle <s>  pulsa «Otra» una vez tras <s> segundos (fichas que se barajan)
//   xcrun simctl launch <udid> com.andreseloy.colorsapp -uiScreen rejilla -uiRejillaDemo -uiAppearance dark
import Foundation
import SwiftUI

struct RejillaLaunchOptions: Equatable, Sendable {
    var demo = false
    var search: String?
    var size: Int?
    var status: RejillaModel.StatusFilter?
    var detailId: Int?
    var detailLarge = false
    var colorSearch = false
    var scrollTo: Int?
    var motionTime: Double?
    var reduceMotion = false
    var autoShuffleAfter: Double?

    static let empty = RejillaLaunchOptions()

    static func parse(_ args: [String]) -> RejillaLaunchOptions {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var o = RejillaLaunchOptions()
        let screen = value("-uiScreen")
        o.demo = screen == "rejilla-demo" || args.contains("-uiRejillaDemo")
        o.search = value("-uiRejillaSearch")
        o.size = value("-uiRejillaSize").flatMap(Int.init).flatMap { (2...4).contains($0) ? $0 : nil }
        o.status = value("-uiRejillaStatus").flatMap(RejillaModel.StatusFilter.init(rawValue:))
        if let screen, screen.hasPrefix("explorar-") {
            o.detailId = Int(screen.dropFirst("explorar-".count))
        }
        if let id = value("-uiRejillaDetail").flatMap(Int.init) { o.detailId = id }
        o.detailLarge = args.contains("-uiRejillaDetailLarge")
        o.colorSearch = args.contains("-uiRejillaColorSearch")
        o.scrollTo = value("-uiRejillaScrollTo").flatMap(Int.init)
        o.motionTime = value("-uiRejillaMotionTime").flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil }
        o.reduceMotion = value("-uiRejillaReduceMotion") == "1"
        o.autoShuffleAfter = value("-uiRejillaAutoShuffle").flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil }
        return o
    }

    /// Opciones del proceso actual; siempre vacías en Release.
    static var current: RejillaLaunchOptions {
        #if DEBUG
        return parse(ProcessInfo.processInfo.arguments)
        #else
        return .empty
        #endif
    }
}

/// Aplica a la pestaña el tiempo congelado y «Reducir movimiento» forzado de los atajos (relojes
/// ambientales de Design/Motion y de la marca). Sin opciones no añade nada.
struct RejillaMotionDebug: ViewModifier {
    let options: RejillaLaunchOptions

    func body(content: Content) -> some View {
        content
            .motionTime(options.motionTime)
            .environment(\.brandFrozenTime, options.motionTime)
            .forceReducedMotion(options.reduceMotion)
            .environment(\.brandReduceMotionOverride, options.reduceMotion ? true : nil)
    }
}

#if DEBUG
/// Datos de ejemplo de la Rejilla: nunca en la base de datos real ni en Release.
enum RejillaDemo {
    /// Marca de los registros de ejemplo (`assetLocalId`).
    static let marker = "ejemplo"
    /// Combinación fija de la tarjeta «Al azar» en las capturas.
    static let randomComboId = 255
    /// Combinaciones guardadas en el Jardín de ejemplo.
    static let savedComboIds = [152, 254]

    /// Desbloqueos de ejemplo: (combinación, días atrás, origen).
    static let unlocks: [(id: Int, daysAgo: Int, source: ScanSource)] = [
        (12, 1, .library), (27, 1, .library), (44, 2, .camera), (58, 2, .library), (95, 3, .picker),
        (103, 3, .library), (152, 4, .library), (184, 5, .camera), (201, 6, .library), (233, 6, .library),
        (254, 7, .picker), (262, 8, .library), (290, 9, .library), (317, 10, .camera), (337, 11, .library),
        (5, 12, .library), (71, 13, .library), (128, 14, .camera), (166, 15, .library), (345, 16, .library),
    ]

    /// Análisis de ejemplo con top-1 (para «Visto en tus análisis» del detalle).
    static let scans: [(top1: Int, daysAgo: Int, source: ScanSource)] = [
        (12, 1, .library), (12, 4, .camera), (152, 4, .library),
    ]

    /// Entorno con base de datos en memoria y el diccionario ya cargado.
    @MainActor
    static func makeEnvironment(dictionary: WadaDictionary) throws -> AppEnvironment {
        AppEnvironment(dictionary: dictionary, database: try AppDatabase.inMemory(), scanRunner: NoopScanRunner(), launches: 0)
    }

    /// Siembra desbloqueos y análisis marcados como ejemplo.
    @MainActor
    static func seed(_ env: AppEnvironment, now: Date = Date()) async throws {
        let day: TimeInterval = 86_400
        for u in unlocks {
            try await env.unlocks.unlock(comboId: u.id, source: u.source, assetLocalId: marker,
                                         at: now.addingTimeInterval(-Double(u.daysAgo) * day - 3_600))
        }
        for (i, s) in scans.enumerated() {
            let at = now.addingTimeInterval(-Double(s.daysAgo) * day - Double(i) * 600)
            let record = ScanRecord(id: UUIDv7.string(now: at), assetLocalId: marker, source: s.source,
                                    top1: s.top1, top2: nil, top3: nil, scores: "[18.5]", paletteJson: "[]",
                                    ambiguous: false, engineVersion: env.engineVersion, dictVersion: env.dictVersion,
                                    scannedAt: at, updatedAt: at, deletedAt: nil, rev: 1, dirty: false)
            try await env.scans.insert(record)
        }
    }

    /// Jardín en memoria con dos combinaciones guardadas.
    @MainActor
    static func makeGarden(now: Date = Date()) -> GardenStore {
        let store = GardenStore(url: nil)
        for id in savedComboIds where !store.isSaved(comboId: id) {
            store.toggle(comboId: id, now: now)
        }
        return store
    }
}
#endif
