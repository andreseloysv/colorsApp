// Hoja «Compartir tarjeta» (Feed y Jardín): vista previa de la tarjeta en claro, elección de
// formato (publicación 4:5 o historia 9:16) y ShareLink con la imagen ya dibujada. La
// imagen se genera en el teléfono con ImageRenderer; nada sale sin la acción del usuario.
import SwiftUI
import UIKit

/// Lo que se comparte: un scan guardado con su foto (si hay).
struct ShareCardRequest: Identifiable {
    let scan: ScanRecord
    let photo: CGImage?
    var initialFormat: ShareCardFormat = .post

    var id: String { scan.id }
}

struct ShareCardSheet: View {
    let request: ShareCardRequest
    let dictionary: WadaDictionary

    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareCardFormat
    @State private var rendered: [ShareCardFormat: UIImage] = [:]

    init(request: ShareCardRequest, dictionary: WadaDictionary) {
        self.request = request
        self.dictionary = dictionary
        _format = State(initialValue: request.initialFormat)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                SegmentedPill(items: ShareCardFormat.allCases.map { (id: $0, title: $0.title) }, selection: $format)
                    .padding(.horizontal, Spacing.margin)
                    .accessibilityIdentifier("share.format")
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Spacing.margin)
                Text("\(format.pixelLabel) px · siempre en claro")
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.onSurfaceVariant)
                shareButton
                    .padding(.horizontal, Spacing.margin)
                    .padding(.bottom, Spacing.sm)
            }
            .padding(.top, Spacing.sm)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Compartir tarjeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .accessibilityIdentifier("share.close")
                }
            }
        }
        .task(id: format) { renderIfNeeded(format) }
        .accessibilityIdentifier("share.sheet")
    }

    @ViewBuilder private var preview: some View {
        let size = format.size
        if let image = rendered[format] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(size.width / size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.outlineVariant.opacity(0.6), lineWidth: 1))
                .elevation(.rest)
                .accessibilityLabel("Vista previa de la tarjeta")
        } else {
            ProgressView()
        }
    }

    @ViewBuilder private var shareButton: some View {
        if let image = rendered[format] {
            let item = Image(uiImage: image)
            ShareLink(item: item, preview: SharePreview(shareTitle, image: item)) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
                    Text("Compartir").textRole(.labelLG)
                }
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(Theme.primary).elevation(.floating))
                .sunGlint(Capsule())
            }
            .buttonStyle(.solarPress)
            .accessibilityIdentifier("share.send")
        } else {
            SolarPrimaryButton(title: "Preparando la tarjeta…", isLoading: true, action: {})
        }
    }

    private var shareTitle: String {
        request.scan.top1.map { "\(AppBrand.name) · Wada \(WadaDictionary.numberLabel($0))" } ?? AppBrand.name
    }

    private func renderIfNeeded(_ format: ShareCardFormat) {
        guard rendered[format] == nil else { return }
        let card = ShareCardRenderer.card(for: request.scan, photo: request.photo, dictionary: dictionary, format: format)
        rendered[format] = ShareCardRenderer.render(card)
    }
}
