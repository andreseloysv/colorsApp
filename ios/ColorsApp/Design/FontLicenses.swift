// Licencias de las fuentes empaquetadas (SIL OFL 1.1). La app no abre URLs (sin red):
// el texto de cada OFL se lee del bundle. Lo enlaza «Acerca de».
// La pantalla que las muestra es `FontLicensesView` (Views/Ajustes/FontLicensesView.swift):
// vive con las demás pantallas secundarias porque usa su marco (FIDELITY.md §7.5).
import SwiftUI

enum FontLicenses {
    struct Entry: Identifiable, Sendable {
        let id: String
        let family: String
        let credit: String
        let resource: String
    }

    static let entries: [Entry] = [
        Entry(id: "literata", family: "Literata",
              credit: "Literata, The Literata Project Authors, SIL Open Font License 1.1.",
              resource: "Literata-OFL"),
        Entry(id: "plusjakartasans", family: "Plus Jakarta Sans",
              credit: "Plus Jakarta Sans, The Plus Jakarta Sans Project Authors, SIL Open Font License 1.1.",
              resource: "PlusJakartaSans-OFL"),
    ]

    /// Texto del OFL empaquetado; nil si falta en el bundle.
    static func text(for entry: Entry, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: entry.resource, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
