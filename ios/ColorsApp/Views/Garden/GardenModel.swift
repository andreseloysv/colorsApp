// Estado de la pestaña Jardín (docs/design/DESIGN_SYSTEM.md §5.4): contadores reales
// (fotos analizadas, desbloqueadas x/348, «Sí, es eso» y acierto), cosechas (scans con
// su veredicto), colecciones por tamaño y guardadas. Lee solo de los repositorios de
// `AppEnvironment`; los textos puros viven en `GardenText` para poder probarlos.
import Foundation
import Combine

@MainActor
final class GardenModel: ObservableObject {
    /// Segmentos del Jardín.
    enum Segment: String, CaseIterable, Identifiable, Sendable {
        case fotos, guardadas, colecciones

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fotos: "Fotos"
            case .guardadas: "Guardadas"
            case .colecciones: "Colecciones"
            }
        }
    }

    /// Colección automática por tamaño («2 colores · 12/120»).
    struct SizeCollection: Identifiable, Hashable, Sendable {
        let size: Int
        let total: Int
        let unlocked: Int
        /// Combinaciones desbloqueadas de ese tamaño, la más reciente primero.
        let recentUnlocked: [Int]

        var id: Int { size }
        var title: String { "\(size) colores" }
        var countText: String { "\(unlocked)/\(total)" }
        var fraction: Double { total > 0 ? Double(unlocked) / Double(total) : 0 }
    }

    /// Scans vivos más recientes (hasta `limit`).
    @Published private(set) var scans: [ScanRecord] = []
    /// Scans guardados en el Jardín (en el orden de `GardenStore`), aunque no estén entre los recientes.
    @Published private(set) var savedScans: [ScanRecord] = []
    /// Total de scans vivos.
    @Published private(set) var scanCount = 0
    /// Desbloqueos vivos por id de combinación.
    @Published private(set) var unlocks: [Int: UnlockRecord] = [:]
    /// Último veredicto por scan.
    @Published private(set) var verdicts: [String: FeedbackVerdict] = [:]
    @Published private(set) var yesVotes = 0
    @Published private(set) var noVotes = 0
    /// true tras la primera carga de scans.
    @Published private(set) var loaded = false
    /// Cuántas cosechas se piden (se amplía con «Ver más»).
    @Published var limit = GardenModel.pageSize

    static let pageSize = 20

    private var paletteCache: [String: [PaletteColor]] = [:]

    init() {}

    var hasMore: Bool { scanCount > scans.count }
    var latestScan: ScanRecord? { scans.first }

    // MARK: Carga

    /// Carga puntual (tests y al volver a la pestaña).
    func refresh(env: AppEnvironment, store: GardenStore) async {
        if let recent = try? await env.scans.recent(limit: limit) {
            scans = recent
        }
        if let all = try? await env.unlocks.all() {
            apply(unlocks: all)
        }
        await refreshCounts(env: env)
        await refreshSaved(env: env, store: store)
        loaded = true
    }

    /// Observa los scans recientes hasta que se cancele la tarea (`.task(id: limit)`).
    func observeScans(env: AppEnvironment, store: GardenStore) async {
        do {
            for try await recent in env.scans.observeRecent(limit: limit) {
                scans = recent
                loaded = true
                await refreshCounts(env: env)
                await refreshSaved(env: env, store: store)
            }
        } catch {
            // Solo falla si se cierra la base de datos: se queda el último valor.
        }
    }

    /// Observa los desbloqueos (contador x/348 y colecciones).
    func observeUnlocks(env: AppEnvironment) async {
        do {
            for try await records in env.unlocks.observeAll() {
                apply(unlocks: records)
            }
        } catch {
            // Último valor conocido.
        }
    }

    /// Recuentos y veredictos (la tabla feedback no tiene observación: se relee al volver a la pestaña).
    func refreshCounts(env: AppEnvironment) async {
        if let n = try? await env.scans.count() { scanCount = n }
        if let all = try? await env.feedback.all() {
            verdicts = GardenText.latestVerdicts(all)
        }
        if let counts = try? await env.feedback.counts() {
            yesVotes = counts.yes
            noVotes = counts.no
        }
    }

    /// Scans guardados: primero de los recientes y, si no están, de la base de datos.
    func refreshSaved(env: AppEnvironment, store: GardenStore) async {
        let byId = Dictionary(scans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [ScanRecord] = []
        for item in store.items where item.kind == .scan {
            if let scan = byId[item.id] {
                out.append(scan)
            } else if let scan = try? await env.scans.fetch(id: item.id), scan.deletedAt == nil {
                out.append(scan)
            }
        }
        savedScans = out
    }

    private func apply(unlocks records: [UnlockRecord]) {
        unlocks = Dictionary(records.map { ($0.comboId, $0) }, uniquingKeysWith: { _, last in last })
    }

    // MARK: Derivados

    /// Paleta con nombres de Wada (motor), calculada una vez por scan y revisión.
    func palette(for scan: ScanRecord, dictionary: WadaDictionary) -> [PaletteColor] {
        let key = "\(scan.id)#\(scan.rev)"
        if let cached = paletteCache[key] { return cached }
        let palette = GardenText.palette(scan, dictionary: dictionary)
        paletteCache[key] = palette
        return palette
    }

    func verdict(for scan: ScanRecord) -> Verdict? {
        verdicts[scan.id].map(GardenText.verdict)
    }

    func sizeCollections(_ dictionary: WadaDictionary) -> [SizeCollection] {
        GardenText.sizeCollections(dictionary: dictionary, unlocks: Array(unlocks.values))
    }
}

/// Textos y cálculos puros del Jardín (sin base de datos ni vistas).
enum GardenText {
    private static let spanish = Locale(identifier: "es_ES")

    /// «Acierto: 82 % (41 de 50 votos)»; sin votos, una invitación a votar.
    static func accuracy(yes: Int, no: Int) -> String {
        let total = yes + no
        guard total > 0 else { return "Vota tus resultados para ver el acierto" }
        let pct = DesignFormat.percent(Double(yes) / Double(total))
        return "Acierto: \(pct) (\(yes) de \(total) \(total == 1 ? "voto" : "votos"))"
    }

    /// Partes de la línea de acierto para pintar el valor en semibold: («Acierto:», «82 % (41 de 50 votos)»);
    /// nil sin votos (entonces se usa `accuracy`).
    static func accuracyParts(yes: Int, no: Int) -> (label: String, value: String)? {
        let total = yes + no
        guard total > 0 else { return nil }
        let pct = DesignFormat.percent(Double(yes) / Double(total))
        return ("Acierto:", "\(pct) (\(yes) de \(total) \(total == 1 ? "voto" : "votos"))")
    }

    /// Fecha y origen de una cosecha por separado («ayer», «Carrete · Ejemplo»): el origen se pinta en
    /// `secondary` como el «Natural Daylight» del ejemplo. `harvestMetadata` = «fecha · origen».
    static func harvestMetadataParts(_ scan: ScanRecord, now: Date = Date(), isExample: Bool = false) -> (date: String, origin: String) {
        var origin = [sourceTitle(scan.source)]
        if isExample { origin.append("Ejemplo") }
        return (relativeDay(scan.scannedAt, now: now), origin.joined(separator: " · "))
    }

    /// «Dominante: Black (#16171D) · 33 %».
    static func dominantLine(_ c: PaletteColor) -> String {
        var s = "Dominante: "
        if let name = c.name { s += "\(name) (\(c.hex))" } else { s += c.hex }
        if let w = c.weight { s += " · \(DesignFormat.percent(w))" }
        return s
    }

    /// Distribución de la ropa: «48 % Khaki · 26 % Brass» (con el nombre de Wada más cercano si lo hay).
    static func distribution(_ palette: [PaletteColor]) -> String {
        palette.compactMap { c -> String? in
            guard let w = c.weight else { return nil }
            return [DesignFormat.percent(w), c.name].compactMap { $0 }.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    /// Combinaciones desbloqueadas desde la última visita al Jardín (insignia «✦» del avatar).
    static func newUnlocks(current: Int, lastSeen: Int) -> Int {
        max(0, current - max(0, lastSeen))
    }

    /// Título de una combinación (mismo criterio que el Feed): nombre aceptado (names.es.json) →
    /// propuesto (names.suggested.json, `ComboNaming`) → nombres de Wada de sus dos primeros
    /// colores («Warm Gray · Black», dictionary.json); sin resultado, «Sin resultado».
    static func comboTitle(_ comboId: Int?, dictionary: WadaDictionary, naming: ComboNaming = .bundled) -> String {
        guard let comboId else { return "Sin resultado" }
        let named = naming.name(for: comboId, in: dictionary)
        if named.kind != .number { return named.text }
        let names = dictionary.colors(ofComboId: comboId).prefix(2).map(\.name)
        return names.isEmpty ? WadaDictionary.numberLabel(comboId) : names.joined(separator: " · ")
    }

    /// Origen con mayúscula inicial («Carrete», «Cámara», «Foto elegida»).
    static func sourceTitle(_ source: ScanSource) -> String {
        switch source {
        case .camera: "Cámara"
        case .picker: "Foto elegida"
        case .library: "Carrete"
        case .manual: "Manual"
        }
    }

    /// «hoy, 10:45», «ayer», «hace 3 días», «14 sept» o «14 sept 2025» (zona horaria del calendario).
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.locale = spanish
        let style = Date.FormatStyle(locale: spanish, calendar: cal, timeZone: cal.timeZone)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case 0:
            return "hoy, " + date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        case 1:
            return "ayer"
        case 2...6:
            return "hace \(days) días"
        default:
            let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
            return sameYear
                ? date.formatted(style.day().month(.abbreviated))
                : date.formatted(style.day().month(.abbreviated).year())
        }
    }

    /// Metadatos de una cosecha: «ayer · Carrete».
    static func harvestMetadata(_ scan: ScanRecord, now: Date = Date(), isExample: Bool = false) -> String {
        var parts = [relativeDay(scan.scannedAt, now: now), sourceTitle(scan.source)]
        if isExample { parts.append("Ejemplo") }
        return parts.joined(separator: " · ")
    }

    /// Etiquetas reales de la variante proporción: «Nº 337» y «Ambigua».
    static func harvestTags(_ scan: ScanRecord) -> [String] {
        var tags: [String] = []
        if let top1 = scan.top1 { tags.append(WadaDictionary.numberLabel(top1)) }
        if scan.ambiguous { tags.append("Ambigua") }
        return tags
    }

    /// Paleta del scan como colores de datos, con el nombre de Wada más cercano (motor).
    static func palette(_ scan: ScanRecord, dictionary: WadaDictionary?) -> [PaletteColor] {
        scan.palette.enumerated().compactMap { i, entry in
            guard let c = PaletteColor(id: i, hex: entry.hex, weight: entry.weight) else { return nil }
            return dictionary.map { c.namedByNearestWada(in: $0) } ?? c
        }
    }

    /// Último veredicto por scan (`feedback.all()` viene del más reciente al más antiguo).
    static func latestVerdicts(_ feedback: [FeedbackRecord]) -> [String: FeedbackVerdict] {
        var out: [String: FeedbackVerdict] = [:]
        for f in feedback where out[f.scanId] == nil {
            out[f.scanId] = f.verdict
        }
        return out
    }

    static func verdict(_ v: FeedbackVerdict) -> Verdict {
        switch v {
        case .yes: .yes
        case .no: .no
        }
    }

    /// Colecciones por tamaño con sus desbloqueadas (más recientes primero).
    static func sizeCollections(dictionary: WadaDictionary, unlocks: [UnlockRecord]) -> [GardenModel.SizeCollection] {
        let sizeById = Dictionary(dictionary.combinations.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })
        let sorted = unlocks.filter { $0.deletedAt == nil }.sorted {
            $0.firstSeenAt != $1.firstSeenAt ? $0.firstSeenAt > $1.firstSeenAt : $0.comboId < $1.comboId
        }
        return dictionary.collectionsBySize.compactMap { collection -> GardenModel.SizeCollection? in
            guard case .bySize(let size) = collection.kind else { return nil }
            let ids = sorted.filter { sizeById[$0.comboId] == size }.map(\.comboId)
            return GardenModel.SizeCollection(size: size, total: collection.comboIds.count, unlocked: ids.count,
                                              recentUnlocked: ids)
        }
    }

    /// «14 sept» (fecha corta de un desbloqueo).
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(spanish))
    }

    /// «12 de 120 en tu rejilla».
    static func collectionProgress(_ c: GardenModel.SizeCollection) -> String {
        "\(c.unlocked) de \(c.total) en tu rejilla"
    }

    /// «5 guardadas» / «1 guardada».
    static func savedCount(_ n: Int) -> String {
        n == 1 ? "1 guardada" : "\(n) guardadas"
    }
}
