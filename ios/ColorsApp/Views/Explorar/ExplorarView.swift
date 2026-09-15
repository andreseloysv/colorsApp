// Pestaña Explorar (PLAN §7.7): búsqueda por número, herramientas ("Buscar
// por color", "Extraer de una foto") y colecciones (curadas y automáticas por
// tamaño) -> combinaciones -> detalle.
import SwiftUI

struct ExplorarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var path = NavigationPath()
    @State private var numberText = ""
    @State private var numberError: String?

    enum Tool: Hashable {
        case colorSearch
        case paletteExtract
    }

    /// "12", " 012 " -> 12; nil si no es un número de 1 a `count`.
    static func parseNumber(_ text: String, count: Int) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), n >= 1, n <= count else { return nil }
        return n
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Buscar por número") {
                    HStack {
                        TextField("1 – \(env.comboCount)", text: $numberText)
                            .keyboardType(.numberPad)
                            .onSubmit(openNumber)
                            .accessibilityIdentifier("explorar.number")
                        Button("Abrir", action: openNumber)
                            .buttonStyle(.borderedProminent)
                            .disabled(numberText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let numberError {
                        Text(numberError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section("Herramientas") {
                    NavigationLink(value: Tool.colorSearch) {
                        Label("Buscar por color", systemImage: "eyedropper.halffull")
                    }
                    NavigationLink(value: Tool.paletteExtract) {
                        Label("Extraer de una foto", systemImage: "photo.on.rectangle.angled")
                    }
                }
                Section("Colecciones") {
                    ForEach(env.dictionary.collections) { collection in
                        NavigationLink(value: collection.id) {
                            HStack {
                                Label(collection.title, systemImage: icon(for: collection))
                                Spacer()
                                Text("\(collection.comboIds.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Explorar")
            .navigationDestination(for: String.self) { collectionId in
                CollectionView(collectionId: collectionId)
            }
            .navigationDestination(for: Int.self) { comboId in
                ComboDetailView(comboId: comboId)
            }
            .navigationDestination(for: Tool.self) { tool in
                switch tool {
                case .colorSearch: ColorSearchView()
                case .paletteExtract: PaletteExtractView()
                }
            }
        }
    }

    private func icon(for collection: WadaCollection) -> String {
        switch collection.kind {
        case .bySize(let n): n <= 2 ? "square.split.2x1" : (n == 3 ? "rectangle.split.3x1" : "square.grid.2x2")
        case .curated: "star"
        }
    }

    private func openNumber() {
        guard let id = Self.parseNumber(numberText, count: env.comboCount) else {
            numberError = "Escribe un número entre 1 y \(env.comboCount)."
            return
        }
        numberError = nil
        numberText = ""
        path.append(id)
    }
}
