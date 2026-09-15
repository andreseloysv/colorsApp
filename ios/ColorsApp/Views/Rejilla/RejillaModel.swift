// Estado de la pestaña Rejilla (PLAN §7.5): desbloqueos observados desde GRDB
// (`UnlockRepository.observeAll`), filtro por tamaño y contador "41/348".
// Separado de la vista para poder probarlo con una AppDatabase temporal.
import Foundation
import Combine

@MainActor
final class RejillaModel: ObservableObject {
    /// Desbloqueos vivos por id de combinación.
    @Published private(set) var unlocks: [Int: UnlockRecord] = [:]
    /// nil = todas; 2, 3 o 4 = solo combinaciones de ese tamaño.
    @Published var sizeFilter: Int? = nil
    /// true tras la primera emisión de la observación (o refresh).
    @Published private(set) var loaded = false

    private var observation: Task<Void, Never>?

    nonisolated init() {}

    var unlockedIds: Set<Int> { Set(unlocks.keys) }
    var unlockedCount: Int { unlocks.count }

    func isUnlocked(_ comboId: Int) -> Bool { unlocks[comboId] != nil }

    func unlock(for comboId: Int) -> UnlockRecord? { unlocks[comboId] }

    /// "41/348".
    nonisolated static func counterText(unlocked: Int, total: Int) -> String { "\(unlocked)/\(total)" }

    func counterText(total: Int) -> String { Self.counterText(unlocked: unlocks.count, total: total) }

    /// Combinaciones visibles con el filtro actual, en orden de id.
    func combos(in dictionary: WadaDictionary) -> [WadaCombo] {
        guard let size = sizeFilter else { return dictionary.combinations }
        return dictionary.combinations.filter { $0.size == size }
    }

    /// Desbloqueadas dentro del filtro actual (para el subtítulo "12 de 120").
    func unlockedCount(in dictionary: WadaDictionary) -> Int {
        guard let size = sizeFilter else { return unlocks.count }
        return unlocks.keys.reduce(0) { acc, id in acc + ((dictionary.combo(id: id)?.size == size) ? 1 : 0) }
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
