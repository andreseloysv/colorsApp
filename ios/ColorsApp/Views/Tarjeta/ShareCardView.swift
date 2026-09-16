// Tarjeta compartible (PLAN §7.4; docs/design/DESIGN_SYSTEM.md §4 n.º 31) con el estilo
// solarpunk: marco pergamino con lavados cálido y verde lejos de los colores, marca
// `AppBrand.name`, foto con radio 12, paleta proporcional y combinación en pocillos
// BLANCOS (zona neutra de juicio de color, §1.4) y nombre en Literata. Siempre en claro,
// sea cual sea el tema del teléfono. Dos formatos: publicación 4:5 (360 × 450 pt →
// 1080 × 1350 px) e historia 9:16 (360 × 640 pt → 1080 × 1920 px) con ImageRenderer a
// escala 3. Sin @EnvironmentObject: ImageRenderer no tiene el entorno de la app.
import SwiftUI
import UIKit
import ColorEngine

/// Formato de la tarjeta.
enum ShareCardFormat: String, CaseIterable, Identifiable, Sendable {
    /// Publicación 4:5 (1080 × 1350 px).
    case post
    /// Historia 9:16 (1080 × 1920 px).
    case story

    var id: String { rawValue }

    /// Tamaño en puntos (a escala 3 da los píxeles).
    var size: CGSize {
        switch self {
        case .post: CGSize(width: 360, height: 450)
        case .story: CGSize(width: 360, height: 640)
        }
    }

    var title: String {
        switch self {
        case .post: "Publicación 4:5"
        case .story: "Historia 9:16"
        }
    }

    var pixelLabel: String {
        let s = size
        return "\(Int(s.width * ShareCardView.renderScale)) × \(Int(s.height * ShareCardView.renderScale))"
    }
}

struct ShareCardView: View {
    /// 360 x 450 pt (formato publicación); a escala 3 son 1080 x 1350 px.
    nonisolated static let size = ShareCardFormat.post.size
    nonisolated static let renderScale: CGFloat = 3

    let photo: CGImage?
    /// Paleta de la foto con su peso (dentro de un pocillo blanco).
    let palette: [PaletteColor]
    /// Colores de la combinación ganadora.
    let comboColors: [PaletteColor]
    /// Nombre de la combinación (curado o «Nº 012»).
    let title: String
    /// «Nº 012».
    let number: String
    /// «Nº 012 · 2 colores» o «2 colores».
    let subtitle: String
    /// Nombre a mostrar en grande cuando no hay nombre curado (propuesto o colores de Wada).
    var displayName: String? = nil
    var format: ShareCardFormat = .post

    private var margin: CGFloat { 18 }

    /// Medidas por formato (el contenido cabe con holgura en 360 × 450 y 360 × 640 pt).
    private struct Layout {
        let photoHeight: CGFloat
        let gap: CGFloat
        let stripHeight: CGFloat
        let nameSize: CGFloat
    }

    private var layout: Layout {
        switch format {
        case .post: Layout(photoHeight: 176, gap: 10, stripHeight: 34, nameSize: 22)
        case .story: Layout(photoHeight: 250, gap: 12, stripHeight: 44, nameSize: 26)
        }
    }

    var body: some View {
        let size = format.size
        VStack(alignment: .leading, spacing: 0) {
            brandRow
                .padding(.bottom, 10)
            photoBlock
                .frame(height: layout.photoHeight)
                .padding(.bottom, layout.gap)
            if format == .story {
                storyPalette
                    .padding(.bottom, layout.gap)
            } else {
                PaletteRibbon(colors: palette, style: .weights, height: 12, wellPadding: 6, wellCornerRadius: Radius.block)
                    .padding(.bottom, layout.gap)
            }
            comboBlock
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, margin)
        .padding(.top, margin)
        .padding(.bottom, 14)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background { frame }
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.displayScale, Self.renderScale)
    }

    private var photoHeight: CGFloat { layout.photoHeight }

    // MARK: Marco (pergamino y lavados, lejos de los pocillos)

    private var frame: some View {
        ZStack {
            Theme.surface
            // Lavados en las esquinas, fuera de la zona de los pocillos (≥ 16 pt).
            SolarWash(kind: .warm, diameter: 200, blur: 56)
                .position(x: format.size.width + 10, y: -30)
            SolarWash(kind: .green, diameter: 180, blur: 56)
                .position(x: -30, y: format.size.height + 50)
        }
        .clipped()
    }

    private var brandRow: some View {
        HStack(spacing: 8) {
            // Emblema de la marca estático (sin reloj ni resplandor: se renderiza a PNG).
            ChromaSolLogo(size: 26, animated: false, glow: false)
            Text(AppBrand.name)
                .font(ShareCardFont.serif(19, weight: .medium))
                .tracking(-0.45)
                .foregroundStyle(Theme.primary)
            Spacer(minLength: 8)
            Text("Wada \(number)")
                .font(ShareCardFont.sans(11, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder private var photoBlock: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if let photo {
            Color.clear
                .overlay {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipShape(shape)
                .background(shape.fill(Theme.containerLow).elevation(.rest))
        } else {
            // Sin foto: la paleta proporcional ocupa su sitio, dentro de su pocillo.
            SwatchWell(padding: 10, cornerRadius: Radius.card) {
                PaletteRibbon(colors: palette, style: .stripes, height: photoHeight - 20, inWell: false)
            }
        }
    }

    private var storyPalette: some View {
        SwatchWell(padding: 10, cornerRadius: Radius.card) {
            VStack(alignment: .leading, spacing: 8) {
                PaletteRibbon(colors: palette, style: .weights, height: 12, inWell: false)
                PaletteRibbon(colors: Array(palette.prefix(5)), style: .droplets(names: true, hex: true, weights: true),
                              dropletSize: 40, inWell: false)
            }
        }
    }

    private var comboBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Se parece a")
                .font(ShareCardFont.sans(11, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.onSurfaceVariant)
            if comboColors.isEmpty {
                Text("Sin combinación")
                    .font(ShareCardFont.serif(layout.nameSize, weight: .semibold))
                    .foregroundStyle(Theme.onSurface)
            } else {
                PaletteRibbon(colors: comboColors, style: .strip, height: layout.stripHeight,
                              wellPadding: 6, wellCornerRadius: Radius.card)
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName ?? title)
                        .font(ShareCardFont.serif(layout.nameSize, weight: .semibold))
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(subtitle)
                        .font(ShareCardFont.sans(12.5, weight: .medium))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text("\(AppBrand.name) · Wada \(number)")
                .font(ShareCardFont.sans(11, weight: .semibold))
                .foregroundStyle(Theme.onSurfaceVariant)
            Spacer(minLength: 0)
            Text("Analizado en el teléfono")
                .font(ShareCardFont.sans(10.5, weight: .medium))
                .foregroundStyle(Theme.onSurfaceVariant)
        }
    }
}

/// Fuentes de tamaño FIJO para la tarjeta (no crece con Dynamic Type); Literata y Plus
/// Jakarta Sans si están registradas, si no las del sistema.
enum ShareCardFont {
    static func serif(_ size: CGFloat, weight: RoleWeight) -> Font {
        guard FontRegistry.status.literata else { return .system(size: size, weight: weight.font, design: .serif) }
        return Font(Typography.familyFont(FontRegistry.literataFamily, size: size, weight: weight) as CTFont)
    }

    static func sans(_ size: CGFloat, weight: RoleWeight) -> Font {
        guard FontRegistry.status.jakarta else { return .system(size: size, weight: weight.font, design: .rounded) }
        return Font(Typography.familyFont(FontRegistry.jakartaFamily, size: size, weight: weight) as CTFont)
    }
}

enum ShareCardRenderer {
    /// Tarjeta de un resultado recién calculado (nombre, número y colores del top-1).
    @MainActor
    static func card(for outcome: ScanOutcome, dictionary: WadaDictionary, format: ShareCardFormat = .post) -> ShareCardView {
        let palette = outcome.result.swatches.enumerated().map { PaletteColor(id: $0.offset, swatch: $0.element, dictionary: dictionary) }
        return card(comboId: outcome.result.hits.first?.comboId, palette: palette, photo: outcome.image,
                    dictionary: dictionary, format: format)
    }

    /// Tarjeta de un scan guardado (Feed y Jardín) con su foto si está disponible.
    @MainActor
    static func card(for scan: ScanRecord, photo: CGImage?, dictionary: WadaDictionary, format: ShareCardFormat = .post) -> ShareCardView {
        card(comboId: scan.top1, palette: FeedPostText.palette(scan, in: dictionary), photo: photo,
             dictionary: dictionary, format: format)
    }

    @MainActor
    private static func card(comboId: Int?, palette: [PaletteColor], photo: CGImage?, dictionary: WadaDictionary,
                             format: ShareCardFormat) -> ShareCardView {
        let combo = comboId.flatMap { dictionary.combo(id: $0) }
        let number = comboId.map(WadaDictionary.numberLabel) ?? "—"
        let title = comboId.map { dictionary.displayName(id: $0) } ?? "Sin resultado"
        let subtitle = combo.map { DesignFormat.comboSubtitle(id: $0.id, size: $0.size) } ?? ""
        let display = comboId.map { FeedComboName.name($0, in: dictionary) }
        return ShareCardView(photo: photo, palette: palette,
                             comboColors: comboId.map { PaletteColor.combo($0, in: dictionary) } ?? [],
                             title: title, number: number, subtitle: subtitle, displayName: display, format: format)
    }

    /// UIImage del tamaño del formato a escala 3 (1080 × 1350 o 1080 × 1920 px).
    @MainActor
    static func render(_ card: ShareCardView, scale: CGFloat = ShareCardView.renderScale) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(card.format.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

extension ShareCardView {
    /// Compatibilidad con el inicializador anterior (entradas de `PaletteBars` y `Color` de la
    /// combinación). Preferir `ShareCardRenderer.card(for:photo:dictionary:format:)`.
    init(photo: CGImage?, palette: [PaletteBars.Entry], comboColors: [Color], title: String, number: String,
         subtitle: String, format: ShareCardFormat = .post) {
        let paletteColors = palette.enumerated().map { i, e in
            PaletteColor(id: i, r: e.r, g: e.g, b: e.b, weight: e.weight)
        }
        let combo = comboColors.enumerated().map { i, color -> PaletteColor in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            return PaletteColor(id: i, r: byte(r), g: byte(g), b: byte(b))
        }
        self.init(photo: photo, palette: paletteColors, comboColors: combo, title: title, number: number,
                  subtitle: subtitle, displayName: nil, format: format)
    }
}
