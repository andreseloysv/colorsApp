// "Extraer de una foto" (PLAN §7.7): PhotosPicker -> EngineBridge.extractPalette
// (solo la capa 2, sin match) -> paleta con pesos. No guarda ningún scan.
import SwiftUI
import PhotosUI
import ColorEngine

struct PaletteExtractView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: CGImage?
    @State private var swatches: [Swatch] = []
    @State private var state: State = .idle

    enum State: Equatable {
        case idle
        case working
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Elegir foto", systemImage: "photo.on.rectangle")
                }
                .disabled(state == .working)
                switch state {
                case .idle:
                    EmptyView()
                case .working:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Extrayendo la paleta…")
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            } footer: {
                Text("Solo la paleta dominante (capa 2 del motor), sin match contra el diccionario. No se guarda nada.")
            }
            if let image {
                Section("Foto") {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if !swatches.isEmpty {
                Section("Paleta") {
                    PaletteBars(entries: PaletteBars.entries(from: swatches))
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Extraer de una foto")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await extract(item) }
        }
    }

    private func extract(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        state = .working
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageLoadingError.unreadable }
            let loaded = try await Task.detached(priority: .userInitiated) { () -> (CGImage, [Swatch]) in
                let cg = try ImageLoading.cgImage(from: data)
                return (cg, try EngineBridge.extractPalette(cgImage: cg))
            }.value
            image = loaded.0
            swatches = loaded.1
            state = .idle
        } catch {
            state = .failed(ErrorText.describe(error))
        }
    }
}
