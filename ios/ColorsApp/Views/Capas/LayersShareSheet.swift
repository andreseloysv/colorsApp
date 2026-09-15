// "Compartir capas": una imagen PNG vertical con las 11 capas, sus números y la
// explicación del top-3 (ImageRenderer), para enviarla cuando algo sale mal.
// Sin @EnvironmentObject (ImageRenderer no tiene el entorno de la app).
import SwiftUI
import UIKit
import ColorEngine

struct LayersShareSheet: View {
    static let width: CGFloat = 720
    static let renderScale: CGFloat = 2

    let stack: LayerStack
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("colorsApp · capas del análisis")
                    .font(.system(size: 26, weight: .bold))
                Text(title)
                    .font(.system(size: 17))
                ForEach(stack.header, id: \.self) { line in
                    Text(line).font(.system(size: 12).monospacedDigit()).foregroundStyle(Color(white: 0.3))
                }
            }
            let imageLayers = stack.layers.filter { $0.kind.rawValue <= InspectorLayer.Kind.labels.rawValue }
            ForEach(Array(stride(from: 0, to: imageLayers.count, by: 2)), id: \.self) { i in
                HStack(alignment: .top, spacing: 16) {
                    card(imageLayers[i])
                    if i + 1 < imageLayers.count {
                        card(imageLayers[i + 1])
                    } else {
                        Spacer().frame(width: cardWidth)
                    }
                }
            }
            if let palette = stack.layer(.palette) {
                header(palette)
                PaletteDetail(rows: stack.swatches)
            }
            if let why = stack.layer(.explanation) {
                header(why)
                ForEach(why.facts, id: \.self) { Text($0).font(.system(size: 12)) }
                ForEach(stack.explanations) { ExplanationCardView(card: $0) }
            }
            if !stack.clusters.isEmpty {
                Text("Clusters descartados o fusionados")
                    .font(.system(size: 15, weight: .semibold))
                ForEach(stack.clusters) { c in
                    Text(String(format: "%@ · peso %.1f %% · %d px — %@", c.hex, c.weight * 100, c.pixels, c.reason))
                        .font(.system(size: 12))
                }
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var cardWidth: CGFloat { (Self.width - 40 - 16) / 2 }

    private func header(_ layer: InspectorLayer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(layer.number) · \(layer.title)")
                .font(.system(size: 17, weight: .bold))
            Text(layer.meaning)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.35))
            if let warning = layer.warning {
                Text("⚠︎ " + warning).font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
    }

    private func card(_ layer: InspectorLayer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            header(layer)
            LayerCanvas(photo: stack.photo, overlay: layer.kind == .photo ? nil : layer.overlay,
                        opacity: layer.defaultOpacity, pixelated: layer.pixelated,
                        poses: layer.kind == .pose ? stack.poses : [],
                        rasterSize: CGSize(width: stack.rasterWidth, height: stack.rasterHeight), maxHeight: 300)
            ForEach(Array(layer.facts.enumerated()), id: \.offset) { _, fact in
                Text(fact).font(.system(size: 11).monospacedDigit()).foregroundStyle(Color(white: 0.25))
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }
}

enum LayersShareRenderer {
    /// UIImage de `LayersShareSheet` (720 pt de ancho a escala 2).
    @MainActor
    static func render(stack: LayerStack, title: String, scale: CGFloat = LayersShareSheet.renderScale) -> UIImage? {
        let renderer = ImageRenderer(content: LayersShareSheet(stack: stack, title: title))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: LayersShareSheet.width, height: nil)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// PNG en tmp (colorsapp-capas-<scan_id>.png) para ShareLink; nil si falla.
    @MainActor
    static func writePNG(stack: LayerStack, scanId: String, title: String? = nil,
                         directory: URL = FileManager.default.temporaryDirectory) -> URL? {
        guard let image = render(stack: stack, title: title ?? "Scan \(scanId)"), let data = image.pngData() else { return nil }
        let url = directory.appendingPathComponent("colorsapp-capas-\(scanId).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
