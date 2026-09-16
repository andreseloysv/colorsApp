// Hoja de detalle de la Rejilla (también la usan el Feed y otras pestañas): `ComboDetailView`
// con su propia pila de navegación, sin barra: la hoja dibuja su fila superior con «Cerrar»
// (por defecto, `dismiss` de la hoja).
import SwiftUI

struct RejillaComboDetailView: View {
    let combo: WadaCombo
    var naming: ComboNaming = .bundled
    var garden: GardenStore?
    var onSearchColor: ((WadaColor) -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ComboDetailView(comboId: combo.id, naming: naming, garden: garden, onSearchColor: onSearchColor,
                            onClose: onClose ?? { dismiss() })
                .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("rejilla.detail.\(combo.id)")
    }

    static func sourceLabel(_ source: ScanSource) -> String { source.label }
}

/// Peticiones de otras pestañas para abrir la Rejilla ya filtrada (p. ej. el Jardín con
/// «3 colores»): `RejillaRequests.shared.open(size: 3)` y después `selectTab(.rejilla)`.
/// La Rejilla aplica la petición al aparecer o en cuanto llega, y la consume.
@MainActor
final class RejillaRequests: ObservableObject {
    struct Request: Equatable, Sendable {
        let serial: Int
        var size: Int?
        var status: RejillaModel.StatusFilter?
        var search: String?
        var comboId: Int?
    }

    static let shared = RejillaRequests()

    @Published private(set) var pending: Request?
    private var serial = 0

    /// Pide abrir la Rejilla con un filtro de tamaño y/o estado, una búsqueda o el detalle de una combinación.
    func open(size: Int? = nil, status: RejillaModel.StatusFilter? = nil, search: String? = nil, comboId: Int? = nil) {
        serial += 1
        pending = Request(serial: serial, size: size, status: status, search: search, comboId: comboId)
    }

    /// Devuelve y borra la petición pendiente.
    func consume() -> Request? {
        defer { pending = nil }
        return pending
    }
}
