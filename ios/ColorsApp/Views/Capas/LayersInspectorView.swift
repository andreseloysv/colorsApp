// Inspector de capas (Resultado > "Ver capas"): las 11 capas del último análisis
// en el orden del pipeline, cada una con su título, una frase de qué significa,
// un control de opacidad para superponerla a la foto y sus números. Abrirlo no
// vuelve a ejecutar Vision ni el motor (LayerStack solo pinta lo guardado);
// "Compartir capas" genera un PNG vertical con todas (LayersShareSheet) para
// enviarlo cuando un color no cuadra.
import SwiftUI
import UIKit
import ColorEngine
import SubjectKit

/// Ruta del NavigationStack de Hoy hacia el inspector (hash por scan y revisión:
/// tras elegir otra persona es otra ruta).
struct LayersRoute: Hashable {
    let outcome: ScanOutcome
    /// Capa a la que desplazarse al abrir (atajo -uiLayer).
    var initialLayer: Int? = nil

    static func == (lhs: LayersRoute, rhs: LayersRoute) -> Bool {
        lhs.outcome.scan.id == rhs.outcome.scan.id && lhs.outcome.scan.rev == rhs.outcome.scan.rev
            && lhs.initialLayer == rhs.initialLayer
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(outcome.scan.id)
        hasher.combine(outcome.scan.rev)
        hasher.combine(initialLayer)
    }
}

@MainActor
final class LayersInspectorModel: ObservableObject {
    let outcome: ScanOutcome
    let dictionary: WadaDictionary
    @Published private(set) var stack: LayerStack?
    /// Opacidad de cada capa (número -> 0...1).
    @Published var opacity: [Int: Double] = [:]
    /// Swatch aislado en la capa 9 (nil = todos).
    @Published private(set) var isolatedSwatch: Int?
    @Published private(set) var isolatedOverlay: CGImage?
    /// PNG de "Compartir capas" en un fichero temporal.
    @Published private(set) var shareURL: URL?

    init(outcome: ScanOutcome, dictionary: WadaDictionary) {
        self.outcome = outcome
        self.dictionary = dictionary
    }

    /// Construye las capas en segundo plano y después el PNG para compartir.
    func load() async {
        guard stack == nil else { return }
        let o = outcome
        let d = dictionary
        let built = await Task.detached(priority: .userInitiated) { LayerStack.build(outcome: o, dictionary: d) }.value
        for layer in built.layers { opacity[layer.number] = layer.defaultOpacity }
        stack = built
        let title = (o.result.hits.first.map { d.displayName(id: $0.comboId) } ?? "Sin resultado")
            + " · " + o.scan.scannedAt.formatted(date: .abbreviated, time: .shortened)
        shareURL = LayersShareRenderer.writePNG(stack: built, scanId: o.scan.id, title: title)
    }

    func opacityBinding(_ number: Int) -> Binding<Double> {
        Binding(get: { self.opacity[number] ?? 1 }, set: { self.opacity[number] = $0 })
    }

    /// Aísla los píxeles de un swatch (tocar de nuevo: todos).
    func toggleIsolation(_ swatch: Int) {
        guard let stack else { return }
        if isolatedSwatch == swatch {
            isolatedSwatch = nil
            isolatedOverlay = nil
            return
        }
        isolatedSwatch = swatch
        isolatedOverlay = LayerBitmaps.labels(stack.labelMap, width: stack.reducedWidth, height: stack.reducedHeight,
                                              swatches: stack.swatches.map(\.swatch), isolate: swatch)
    }
}

struct LayersInspectorView: View {
    @StateObject private var model: LayersInspectorModel
    private let initialLayer: Int?

    init(model: LayersInspectorModel, initialLayer: Int? = nil) {
        _model = StateObject(wrappedValue: model)
        self.initialLayer = initialLayer
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let stack = model.stack {
                    VStack(alignment: .leading, spacing: 28) {
                        header(stack)
                        ForEach(stack.layers) { layer in
                            LayerCardView(layer: layer, stack: stack, model: model)
                                .id(layer.number)
                        }
                    }
                    .padding()
                } else {
                    ProgressView("Preparando las capas…")
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: model.stack == nil) { _, isNil in
                guard !isNil, let initialLayer else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    proxy.scrollTo(initialLayer, anchor: .top)
                }
            }
        }
        .navigationTitle("Capas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = model.shareURL {
                    ShareLink(item: url) {
                        Label("Compartir capas", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("layers.share")
                } else {
                    ProgressView()
                }
            }
        }
        .task { await model.load() }
    }

    private func header(_ stack: LayerStack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(stack.notice.text, systemImage: stack.notice.systemImage)
                .font(.subheadline)
                .foregroundStyle(stack.notice.isFallback ? Color.orange : Color.secondary)
            ForEach(stack.header.dropFirst(), id: \.self) { line in
                Text(line).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("Cada capa sale del mismo análisis. Desliza la opacidad para compararla con la foto.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Tarjeta de una capa.
struct LayerCardView: View {
    let layer: InspectorLayer
    let stack: LayerStack
    @ObservedObject var model: LayersInspectorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(layer.number)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                Text(layer.title)
                    .font(.title3.bold())
            }
            Text(layer.meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            visual
            if let warning = layer.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(Array(layer.facts.enumerated()), id: \.offset) { _, fact in
                Text(fact)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            extra
        }
        .accessibilityIdentifier("layers.card.\(layer.number)")
    }

    @ViewBuilder
    private var visual: some View {
        switch layer.kind {
        case .photo:
            LayerCanvas(photo: stack.photo, overlay: nil, opacity: 0, pixelated: false, poses: [],
                        rasterSize: CGSize(width: stack.rasterWidth, height: stack.rasterHeight))
        case .palette, .explanation:
            EmptyView()
        default:
            let overlay = layer.kind == .labels ? (model.isolatedOverlay ?? layer.overlay) : layer.overlay
            LayerCanvas(photo: stack.photo, overlay: overlay, opacity: model.opacity[layer.number] ?? layer.defaultOpacity,
                        pixelated: layer.pixelated, poses: layer.kind == .pose ? stack.poses : [],
                        rasterSize: CGSize(width: stack.rasterWidth, height: stack.rasterHeight))
            if overlay != nil || layer.kind == .pose {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Slider(value: model.opacityBinding(layer.number), in: 0...1)
                        .accessibilityLabel("Opacidad de \(layer.title)")
                    Text(String(format: "%.0f %%", (model.opacity[layer.number] ?? layer.defaultOpacity) * 100))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var extra: some View {
        switch layer.kind {
        case .labels:
            LabelsDetail(stack: stack, model: model)
        case .palette:
            PaletteDetail(rows: stack.swatches)
        case .explanation:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(stack.explanations) { card in
                    ExplanationCardView(card: card)
                }
            }
        default:
            EmptyView()
        }
    }
}

/// Foto con una capa superpuesta (misma relación de aspecto) y, en la capa 5, el esqueleto.
struct LayerCanvas: View {
    let photo: CGImage
    let overlay: CGImage?
    let opacity: Double
    let pixelated: Bool
    let poses: [(pose: Pose, colorIndex: Int)]
    let rasterSize: CGSize
    var maxHeight: CGFloat = 360

    var body: some View {
        Image(decorative: photo, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        if let overlay {
                            Image(decorative: overlay, scale: 1)
                                .resizable()
                                .interpolation(pixelated ? .none : .medium)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .opacity(opacity)
                        }
                        if !poses.isEmpty {
                            SkeletonShape(poses: poses, rasterSize: rasterSize)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .opacity(max(0.35, opacity))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Esqueleto de la pose (huesos y articulaciones con confianza > 0) en píxeles del raster.
struct SkeletonShape: View {
    let poses: [(pose: Pose, colorIndex: Int)]
    let rasterSize: CGSize

    static let bones: [(Joint, Joint)] = [
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder), (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip), (.neck, .root),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            guard rasterSize.width > 0, rasterSize.height > 0 else { return }
            let sx = size.width / rasterSize.width, sy = size.height / rasterSize.height
            for (pose, colorIndex) in poses {
                let c = LayerBitmaps.personColor(colorIndex)
                let color = Color(rgb8: c.r, c.g, c.b)
                func point(_ j: Joint) -> CGPoint? {
                    let k = pose[j]
                    guard k.confidence > 0, k.x.isFinite, k.y.isFinite else { return nil }
                    return CGPoint(x: k.x * sx, y: k.y * sy)
                }
                var path = Path()
                for (a, b) in Self.bones {
                    if let p = point(a), let q = point(b) {
                        path.move(to: p)
                        path.addLine(to: q)
                    }
                }
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                for j in Joint.allCases {
                    if let p = point(j) {
                        let r: CGFloat = 4
                        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
                        context.fill(Path(ellipseIn: CGRect(x: p.x - r + 1.5, y: p.y - r + 1.5, width: 2 * r - 3, height: 2 * r - 3)), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Capa 9: swatches que se pueden aislar y clusters descartados o fusionados.
struct LabelsDetail: View {
    let stack: LayerStack
    @ObservedObject var model: LayersInspectorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stack.swatches) { row in
                        Button {
                            model.toggleIsolation(row.index)
                        } label: {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(swatch: row.swatch))
                                    .frame(width: 22, height: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                                Text("\(row.index + 1) · \(row.pixels) px")
                                    .font(.caption.monospacedDigit())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(model.isolatedSwatch == row.index ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("layers.swatch.\(row.index)")
                    }
                }
            }
            if model.isolatedSwatch != nil {
                Text("Mostrando solo los píxeles del color \((model.isolatedSwatch ?? 0) + 1). Tócalo otra vez para ver todos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if stack.clusters.isEmpty {
                Text("Ningún cluster se fusionó ni se descartó.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Clusters que no llegaron tal cual a la paleta")
                    .font(.subheadline.bold())
                ForEach(stack.clusters) { c in
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(rgb8: c.rgb.0, c.rgb.1, c.rgb.2))
                            .frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%@ · peso %.1f %% · %d px", c.hex, c.weight * 100, c.pixels))
                                .font(.caption.monospacedDigit())
                            Text(c.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// Capa 10: paleta con porcentajes y el color más cercano del diccionario.
struct PaletteDetail: View {
    let rows: [SwatchRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaletteBars(entries: PaletteBars.entries(from: rows.map(\.swatch)))
            ForEach(rows) { row in
                Text(String(format: "%d. %@ %.1f %% · %d px · más cercano del diccionario: %@ (%@, ΔE00 %.2f)",
                            row.index + 1, row.swatch.hex, row.swatch.weight * 100, row.pixels,
                            row.nearestColorName, row.nearestColorHex, row.nearestDeltaE))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Capa 11: una combinación del top-3 y por qué tiene su score.
struct ExplanationCardView: View {
    let card: ExplanationCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(card.rank)º")
                    .font(.headline.monospacedDigit())
                SwatchStrip(colors: card.comboHexes.compactMap { Color(hex: $0) }, height: 24)
                    .frame(width: 80)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.title).font(.headline)
                    Text(String(format: "Score %.2f", card.score)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Color de la foto").font(.caption2.bold())
                    Text("Más cercano de la combinación").font(.caption2.bold())
                    Text("ΔE00").font(.caption2.bold()).gridColumnAlignment(.trailing)
                }
                ForEach(card.swatchLines) { line in
                    GridRow {
                        HStack(spacing: 4) {
                            chip(line.swatchHex)
                            Text(String(format: "%d · %.0f %%", line.swatch + 1, line.swatchWeight * 100))
                                .font(.caption.monospacedDigit())
                        }
                        HStack(spacing: 4) {
                            chip(line.colorHex)
                            Text(line.colorName).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Text(String(format: "%.2f", line.deltaE)).font(.caption.monospacedDigit())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Ajuste %.2f · cobertura %.2f · penalización %.2f", card.fitTerm, card.coverageTerm, card.hypothesisPenalty))
                    .font(.caption.monospacedDigit())
                Text("Hipótesis: \(card.hypothesis)")
                    .font(.caption)
                if !card.colorLines.isEmpty {
                    Text("Cobertura: " + card.colorLines.map { String(format: "%@ → color %d (%.2f)", $0.colorName, $0.nearestSwatch + 1, $0.deltaE) }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(card.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .accessibilityIdentifier("layers.explain.\(card.rank)")
    }

    private func chip(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex) ?? .clear)
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary))
    }
}
