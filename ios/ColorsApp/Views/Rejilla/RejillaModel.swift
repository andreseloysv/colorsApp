// Estado de la pestaña Rejilla (PLAN §7.5, docs/design/DESIGN_SYSTEM.md §5.3): desbloqueos
// observados desde GRDB (`UnlockRepository.observeAll`), filtros por tamaño (2/3/4) y por
// estado (desbloqueadas/bloqueadas), texto del buscador y contador «41/348».
// Separado de la vista para poder probarlo con una AppDatabase temporal.
import Foundation
import Combine

@MainActor
final class RejillaModel: ObservableObject {
    /// Filtro por estado en la rejilla.
    enum StatusFilter: String, CaseIterable, Sendable {
        case unlocked, locked

        var title: String {
            switch self {
            case .unlocked: "Desbloqueadas"
            case .locked: "Bloqueadas"
            }
        }
    }

    /// Desbloqueos vivos por id de combinación.
    @Published private(set) var unlocks: [Int: UnlockRecord] = [:]
    /// nil = todas; 2, 3 o 4 = solo combinaciones de ese tamaño.
    @Published var sizeFilter: Int? = nil
    /// nil = todas; si no, solo desbloqueadas o solo bloqueadas.
    @Published var statusFilter: StatusFilter? = nil
    /// Texto del buscador (nombre, número o #hex).
    @Published var searchText: String = ""
    /// true tras la primera emisión de la observación (o refresh).
    @Published private(set) var loaded = false

    nonisolated init() {}

    var unlockedIds: Set<Int> { Set(unlocks.keys) }
    var unlockedCount: Int { unlocks.count }

    func isUnlocked(_ comboId: Int) -> Bool { unlocks[comboId] != nil }

    func unlock(for comboId: Int) -> UnlockRecord? { unlocks[comboId] }

    /// "41/348".
    nonisolated static func counterText(unlocked: Int, total: Int) -> String { "\(unlocked)/\(total)" }

    func counterText(total: Int) -> String { Self.counterText(unlocked: unlocks.count, total: total) }

    /// Consulta interpretada del buscador.
    func query(total: Int) -> RejillaSearch.Query {
        RejillaSearch.interpret(searchText, count: total)
    }

    /// true si hay búsqueda o algún filtro activo.
    var isFiltering: Bool {
        sizeFilter != nil || statusFilter != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Combinaciones con los filtros de tamaño y estado (sin buscador), en orden de id.
    func combos(in dictionary: WadaDictionary) -> [WadaCombo] {
        dictionary.combinations.filter { combo in
            if let size = sizeFilter, combo.size != size { return false }
            switch statusFilter {
            case .unlocked: return isUnlocked(combo.id)
            case .locked: return !isUnlocked(combo.id)
            case nil: return true
            }
        }
    }

    /// Lo que muestra la cuadrícula: filtros + buscador.
    func results(in dictionary: WadaDictionary, index: RejillaSearch.Index) -> [WadaCombo] {
        RejillaSearch.filter(combos(in: dictionary), query: query(total: dictionary.combinations.count), index: index)
    }

    /// Combinaciones del filtro de tamaño (sin estado ni buscador): denominador de «12 de 120».
    func sizeScope(in dictionary: WadaDictionary) -> [WadaCombo] {
        guard let size = sizeFilter else { return dictionary.combinations }
        return dictionary.combinations.filter { $0.size == size }
    }

    /// Desbloqueadas dentro del filtro de tamaño (para «12 de 120 desbloqueadas»).
    func unlockedCount(in dictionary: WadaDictionary) -> Int {
        guard let size = sizeFilter else { return unlocks.count }
        return unlocks.keys.reduce(0) { acc, id in acc + ((dictionary.combo(id: id)?.size == size) ? 1 : 0) }
    }

    /// «12 de 120 desbloqueadas» / «20 de 348 desbloqueadas».
    func progressText(in dictionary: WadaDictionary) -> String {
        "\(unlockedCount(in: dictionary)) de \(sizeScope(in: dictionary).count) desbloqueadas"
    }

    /// Quita búsqueda y filtros.
    func clearFilters() {
        sizeFilter = nil
        statusFilter = nil
        searchText = ""
    }

    /// Carga puntual (tests y previews).
    func refresh(_ repository: UnlockRepository) async throws {
        apply(try await repository.all())
    }

    /// Observa los desbloqueos hasta que se cancele la tarea (`.task` de la vista).
    func observe(_ repository: UnlockRepository) async {
        do {
            for try await records in repository.observeAll() {
                apply(records)
            }
        } catch {
            // La observación solo falla si la base de datos se cierra; la vista
            // se queda con el último valor conocido.
        }
    }

    private func apply(_ records: [UnlockRecord]) {
        unlocks = Dictionary(records.map { ($0.comboId, $0) }, uniquingKeysWith: { _, last in last })
        loaded = true
    }
}

/// Combinación al azar (tarjeta «Al azar»): distinta de la actual cuando hay más de una.
enum RejillaRandom {
    static func next<G: RandomNumberGenerator>(after current: Int?, total: Int, using generator: inout G) -> Int {
        guard total > 1 else { return 1 }
        var id = Int.random(in: 1...total, using: &generator)
        if let current, id == current {
            id = id % total + 1
        }
        return id
    }

    static func next(after current: Int?, total: Int) -> Int {
        var g = SystemRandomNumberGenerator()
        return next(after: current, total: total, using: &g)
    }
}

/// Fechas cortas en español: «14 sept» (este año) o «14 sept 2025».
enum RejillaDateText {
    private static let spanish = Locale(identifier: "es_ES")

    static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: spanish, calendar: calendar)
            .day().month(.abbreviated)
        return sameYear ? date.formatted(style) : date.formatted(style.year())
    }

    /// «14 sept 2026, 10:45».
    static func long(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(Date.FormatStyle(locale: spanish, calendar: calendar).day().month(.abbreviated).year().hour().minute())
    }
}
