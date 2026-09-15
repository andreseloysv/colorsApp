// Tarjeta compartible (PLAN §7.4): vista SwiftUI de 360 x 450 pt (4:5) que
// ImageRenderer(scale: 3) convierte en un UIImage de 1080 x 1350 px: la foto
// recortada, la paleta con su peso, los swatches de la combinación, el nombre
// (curado o "Nº 012") y la marca "colorsApp · Wada Nº 012". Sin
// @EnvironmentObject: ImageRenderer no tiene el entorno de la app.
import SwiftUI
import UIKit
import ColorEngine

struct ShareCardView: View {
    /// 360 x 450 pt; a escala 3 son 1080 x 1350 px.
    static let size = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3

    let photo: CGImage?
    let palette: [PaletteBars.Entry]
    let comboColors: [Color]
    let title: String
    let number: String
    let subtitle: String

    private let photoHeight: CGFloat = 250
    private let paletteHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.92)
                if let photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: Self.size.width, height: photoHeight)
            .clipped()

            HStack(spacing: 0) {
                ForEach(palette) { entry in
                    Rectangle()
                        .fill(entry.color)
                        .frame(width: max(1, Self.size.width * min(1, max(0, entry.weight))))
                }
            }
            .frame(width: Self.size.width, height: paletteHeight, alignment: .leading)
            .clipped()
            .background(Color(white: 0.92))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(comboColors.enumerated()), id: \.offset) { _, color in
                        Rectangle().fill(color)
                    }
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.35))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("colorsApp · Wada \(number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.3))
            }
            .padding(16)
            .frame(width: Self.size.width, height: Self.size.height - photoHeight - paletteHeight, alignment: .topLeading)
            .background(Color.white)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color.white)
    }
}

enum ShareCardRenderer {
    /// Tarjeta de un resultado (nombre, número y colores del top-1).
    static func card(for outcome: ScanOutcome, dictionary: WadaDictionary) -> ShareCardView {
        let comboId = outcome.result.hits.first?.comboId
        let combo = comboId.flatMap { dictionary.combo(id: $0) }
        let number = comboId.map(WadaDictionary.numberLabel) ?? "—"
        let title = comboId.map { dictionary.displayName(id: $0) } ?? "Sin resultado"
        let subtitle: String
        if let combo {
            let hasCurated = comboId.map { dictionary.curatedName(id: $0) != nil } ?? false
            subtitle = hasCurated ? "\(number) · \(comboSubtitle(combo))" : comboSubtitle(combo)
        } else {
            subtitle = ""
        }
        return ShareCardView(photo: outcome.image,
                             palette: PaletteBars.entries(from: outcome.result.swatches),
                             comboColors: combo.map { dictionary.colors(of: $0).map { Color(wada: $0) } } ?? [],
                             title: title, number: number, subtitle: subtitle)
    }

    /// UIImage de 1080 x 1350 px (escala 3 sobre 360 x 450 pt).
    @MainActor
    static func render(_ card: ShareCardView, scale: CGFloat = ShareCardView.renderScale) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(ShareCardView.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
