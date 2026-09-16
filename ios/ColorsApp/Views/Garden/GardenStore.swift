// «Guardar» y colecciones propias del Jardín, v1 (docs/design/DESIGN_SYSTEM.md §5.5-2):
// JSON local en Application Support/ColorsApp/garden.json con
// `[{kind: scan|combo, id, folder?, savedAt}]`, observable. Sin red ni cuentas. La v2
// (tabla `garden_items` sync-ready) es cosa del equipo dueño de ios/ColorsApp/DB/**.
// Lo usan el Jardín (Guardadas) y, si lo necesitan, el Feed («Guardar») y la Rejilla (hoja).
import Foundation
import Combine

@MainActor
final class GardenStore: ObservableObject {
    struct Item: Codable, Hashable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable {
            /// Un análisis (`ScanRecord.id`).
            case scan
            /// Una combinación de Wada (id 1…348 como texto).
            case combo
        }

        var kind: Kind
        var id: String
        /// Carpeta propia (nil = sin carpeta). Reservado: la interfaz aún no crea carpetas.
        var folder: String?
        var savedAt: Date

        /// Clave única «scan:<uuid>» / «combo:67».
        var key: String { "\(kind.rawValue):\(id)" }
    }

    /// Lo que se guarda en disco (versión del formato + elementos).
    private struct File: Codable {
        var version: Int
        var items: [Item]
    }

    static let fileName = "garden.json"
    static let formatVersion = 1

    /// Almacén de la app: junto a la base de datos (Application Support/ColorsApp/garden.json).
    static let shared = GardenStore(url: AppDatabase.defaultURL.deletingLastPathComponent()
        .appendingPathComponent(fileName))

    /// Elementos guardados, más reciente primero.
    @Published private(set) var items: [Item] = []
    /// Último error de escritura (nil si todo fue bien).
    @Published private(set) var lastError: String?

    /// nil = solo en memoria (tests, datos de ejemplo).
    let url: URL?

    init(url: URL?) {
        self.url = url
        items = Self.load(url: url)
    }

    // MARK: Consulta

    var savedScanIds: Set<String> { Set(items.filter { $0.kind == .scan }.map(\.id)) }
    var savedComboIds: Set<Int> { Set(items.filter { $0.kind == .combo }.compactMap { Int($0.id) }) }

    func isSaved(scanId: String) -> Bool { items.contains { $0.kind == .scan && $0.id == scanId } }
    func isSaved(comboId: Int) -> Bool { items.contains { $0.kind == .combo && $0.id == String(comboId) } }

    // MARK: Cambios

    /// Guarda o quita un análisis. Devuelve true si queda guardado.
    @discardableResult
    func toggle(scanId: String, now: Date = Date()) -> Bool {
        toggle(Item(kind: .scan, id: scanId, folder: nil, savedAt: now))
    }

    /// Guarda o quita una combinación. Devuelve true si queda guardada.
    @discardableResult
    func toggle(comboId: Int, now: Date = Date()) -> Bool {
        toggle(Item(kind: .combo, id: String(comboId), folder: nil, savedAt: now))
    }

    func save(scanId: String, now: Date = Date()) {
        guard !isSaved(scanId: scanId) else { return }
        insert(Item(kind: .scan, id: scanId, folder: nil, savedAt: now))
    }

    func remove(scanId: String) {
        items.removeAll { $0.kind == .scan && $0.id == scanId }
        persist()
    }

    /// Quita los análisis que ya no existen (borrados del Feed o por «Rehacer escaneo»).
    func prune(liveScanIds: Set<String>) {
        let before = items.count
        items.removeAll { $0.kind == .scan && !liveScanIds.contains($0.id) }
        if items.count != before { persist() }
    }

    private func toggle(_ item: Item) -> Bool {
        if items.contains(where: { $0.key == item.key }) {
            items.removeAll { $0.key == item.key }
            persist()
            return false
        }
        insert(item)
        return true
    }

    private func insert(_ item: Item) {
        items.insert(item, at: 0)
        items.sort { $0.savedAt > $1.savedAt }
        persist()
    }

    // MARK: Disco

    private static func load(url: URL?) -> [Item] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data) else { return [] }
        return file.items.sorted { $0.savedAt > $1.savedAt }
    }

    private func persist() {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(File(version: Self.formatVersion, items: items))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }
}
