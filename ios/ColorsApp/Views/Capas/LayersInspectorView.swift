// Visor de capas tipo historias (docs/design/DESIGN_SYSTEM.md §4 n.º 30 y §5.2 «Ver capas»):
// las 11 capas del último análisis en el orden del pipeline, a pantalla completa sobre el
// neutro #121212 (`Theme.storyBackdrop`):
//   - arriba, 11 segmentos de progreso (tocar uno salta a esa capa), «9 · Asignación a
//     colores», compartir (PNG vertical con todas: LayersShareSheet, id `layers.share`) y cerrar;
//   - en medio, la foto con la capa superpuesta; tocar el tercio izquierdo = anterior, el resto
//     = siguiente; mantener pulsado = ocultar la interfaz para ver la capa limpia; deslizar
//     hacia abajo = cerrar. Sin avance automático: cada capa se lee a su ritmo;
//   - abajo, un panel oscuro neutro (radio 24) con el título, qué significa, el aviso, los
//     números y la opacidad; en la capa 9, los colores para aislar sus píxeles; las capas 10
//     y 11 (paleta y por qué ganó) abren el panel expandido con desplazamiento.
// Abrirlo no vuelve a ejecutar Vision ni el motor (LayerStack solo pinta lo guardado). Los
// colores de datos del panel van en pocillos neutros (#303030 en el visor, blanco en el PNG).
import SwiftUI
import UIKit
import ColorEngine
import SubjectKit

/// Ruta hacia el visor (hash por scan y revisión: tras elegir otra persona es otra ruta).
struct LayersRoute: Hashable, Identifiable {
    let outcome: ScanOutcome
    /// Capa con la que abrir (atajo -uiLayer, 1...11).
    var initialLayer: Int? = nil

    var id: String { "\(outcome.scan.id)#\(outcome.scan.rev)#\(initialLayer ?? 0)" }

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

// MARK: - Visor

struct LayersInspectorView: View {
    @StateObject private var model: LayersInspectorModel
    private let initialLayer: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var current = 0
    @State private var hideUI = false
    @State private var dragOffset: CGFloat = 0
    @State private var didSetInitial = false

    init(model: LayersInspectorModel, initialLayer: Int? = nil) {
        _model = StateObject(wrappedValue: model)
        self.initialLayer = initialLayer
    }

    /// Índice 0-based de la capa con la que se abre.
    nonisolated static func startIndex(initialLayer: Int?, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max((initialLayer ?? 1) - 1, 0), count - 1)
    }

    /// Índice tras tocar en `x` de un ancho `width`: tercio izquierdo = anterior, resto = siguiente.
    nonisolated static func index(afterTapAt x: CGFloat, width: CGFloat, current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        if x < width / 3 { return max(current - 1, 0) }
        return min(current + 1, count - 1)
    }

    var body: some View {
        ZStack {
            Theme.storyBackdrop.ignoresSafeArea()
            if let stack = model.stack, !stack.layers.isEmpty {
                viewer(stack)
            } else {
                VStack(spacing: Spacing.md) {
                    ProgressView().tint(.white)
                    Text("Preparando las capas…").textRole(.labelLG).foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .offset(y: max(0, dragOffset))
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(hideUI)
        .task { await model.load() }
        .onChange(of: model.stack == nil) { _, isNil in
            guard !isNil, !didSetInitial, let stack = model.stack else { return }
            didSetInitial = true
            current = Self.startIndex(initialLayer: initialLayer, count: stack.layers.count)
        }
        .accessibilityIdentifier("layers.viewer")
    }

    private func viewer(_ stack: LayerStack) -> some View {
        let index = min(current, stack.layers.count - 1)
        let layer = stack.layers[index]
        return VStack(spacing: 0) {
            if !hideUI {
                topBar(stack, layer: layer, index: index)
                    .transition(.opacity)
            }
            canvas(stack, layer: layer, index: index)
            if !hideUI {
                StoryLayerPanel(layer: layer, stack: stack, model: model, count: stack.layers.count,
                                showsHint: index == 0)
                    .id(layer.number)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: hideUI)
    }

    private func topBar(_ stack: LayerStack, layer: InspectorLayer, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            StoryProgressBar(count: stack.layers.count, current: index, onSelect: { select($0, in: stack) })
                .padding(.top, Spacing.sm)
                .accessibilityIdentifier("layers.progress")
            HStack(spacing: Spacing.sm) {
                Text("\(layer.number) · \(layer.title)")
                    .textRole(.labelLG)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("layers.title")
                Spacer(minLength: Spacing.sm)
                if let url = model.shareURL {
                    ShareLink(item: url) { barIcon("square.and.arrow.up") }
                        .accessibilityLabel("Compartir capas")
                        .accessibilityIdentifier("layers.share")
                } else {
                    ProgressView().tint(.white).frame(width: Sizes.minTouch, height: Sizes.minTouch)
                }
                Button { dismiss() } label: { barIcon("xmark") }
                    .accessibilityLabel("Cerrar capas")
                    .accessibilityIdentifier("layers.close")
            }
        }
        .padding(.horizontal, Spacing.margin)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func barIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .frame(width: Sizes.minTouch, height: Sizes.minTouch)
            .contentShape(Rectangle())
    }

    private func canvas(_ stack: LayerStack, layer: InspectorLayer, index: Int) -> some View {
        GeometryReader { geo in
            let overlay: CGImage? = {
                switch layer.kind {
                case .photo, .palette, .explanation: return nil
                case .labels: return model.isolatedOverlay ?? layer.overlay
                default: return layer.overlay
                }
            }()
            LayerCanvas(photo: stack.photo, overlay: overlay,
                        opacity: model.opacity[layer.number] ?? layer.defaultOpacity,
                        pixelated: layer.pixelated, poses: layer.kind == .pose ? stack.poses : [],
                        rasterSize: CGSize(width: stack.rasterWidth, height: stack.rasterHeight),
                        maxHeight: geo.size.height, cornerRadius: hideUI ? 0 : Radius.card)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    if hideUI {
                        hideUI = false
                    } else {
                        select(Self.index(afterTapAt: location.x, width: geo.size.width, current: index,
                                          count: stack.layers.count), in: stack)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.35) { hideUI.toggle() }
                .gesture(DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        if value.translation.height > abs(value.translation.width) { dragOffset = value.translation.height }
                    }
                    .onEnded { value in
                        if value.translation.height > 110, value.translation.height > abs(value.translation.width) {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                        }
                    })
                .accessibilityElement()
                .accessibilityLabel("Capa \(layer.number) de \(stack.layers.count): \(layer.title)")
                .accessibilityHint("Desliza arriba o abajo con un dedo para cambiar de capa")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: select(min(index + 1, stack.layers.count - 1), in: stack)
                    case .decrement: select(max(index - 1, 0), in: stack)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("layers.canvas")
        }
        .padding(.horizontal, hideUI ? 0 : Spacing.sm)
        .padding(.vertical, hideUI ? 0 : Spacing.sm)
    }

    private func select(_ index: Int, in stack: LayerStack) {
        guard stack.layers.indices.contains(index) else { return }
        if stack.layers[index].kind != .labels, model.isolatedSwatch != nil, let swatch = model.isolatedSwatch {
            model.toggleIsolation(swatch)
        }
        withAnimation(.easeOut(duration: 0.15)) { current = index }
    }
}

// MARK: - Panel inferior

/// Panel de una capa: título, significado, aviso, datos, opacidad y extras (capas 9–11).
struct StoryLayerPanel: View {
    let layer: InspectorLayer
    let stack: LayerStack
    @ObservedObject var model: LayersInspectorModel
    let count: Int
    var showsHint = false

    private var expanded: Bool { layer.kind == .palette || layer.kind == .explanation }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Capa \(layer.number) de \(count)").textRole(.overline).foregroundStyle(.white.opacity(0.6))
                    Text(layer.title).textRole(.headlineMD).foregroundStyle(.white)
                        .accessibilityIdentifier("layers.panel.title")
                    Text(layer.meaning).textRole(.bodyMD).foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning = layer.warning {
                    Label {
                        Text(warning).textRole(.bodySM).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Theme.secondaryFixedDim)
                    .accessibilityIdentifier("layers.warning")
                }
                // En la paleta final los números ya van en el pocillo de colores (PaletteDetail).
                if !layer.facts.isEmpty, layer.kind != .palette {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(layer.facts.enumerated()), id: \.offset) { _, fact in
                            Text(fact)
                                .textRole(.bodySM)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.74))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("layers.facts")
                }
                opacityControl
                extra
                if showsHint {
                    Text("Toca a la izquierda para volver y a la derecha para seguir. Mantén pulsado para ver la capa limpia; desliza hacia abajo para cerrar.")
                        .textRole(.bodySM)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: expanded ? 520 : 300)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color(white: 0.09).opacity(0.94))
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityIdentifier("layers.panel.\(layer.number)")
    }

    @ViewBuilder private var opacityControl: some View {
        let hasOverlay = layer.overlay != nil || layer.kind == .pose
        if hasOverlay, ![.photo, .palette, .explanation].contains(layer.kind) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.white.opacity(0.7)).accessibilityHidden(true)
                Slider(value: model.opacityBinding(layer.number), in: 0...1)
                    .tint(.white)
                    .accessibilityLabel("Opacidad de \(layer.title)")
                    .accessibilityIdentifier("layers.opacity")
                Text(DesignFormat.percent(model.opacity[layer.number] ?? layer.defaultOpacity))
                    .textRole(.labelMD)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private var extra: some View {
        switch layer.kind {
        case .labels:
            LabelsDetail(stack: stack, model: model)
        case .palette:
            PaletteDetail(rows: stack.swatches)
        case .explanation:
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(stack.explanations) { card in
                    ExplanationCardView(card: card)
                }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Lienzo

/// Foto con una capa superpuesta (misma relación de aspecto) y, en la capa 5, el esqueleto.
struct LayerCanvas: View {
    let photo: CGImage
    let overlay: CGImage?
    let opacity: Double
    let pixelated: Bool
    let poses: [(pose: Pose, colorIndex: Int)]
    let rasterSize: CGSize
    var maxHeight: CGFloat = 360
    var cornerRadius: CGFloat = 10

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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
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

// MARK: - Detalles de las capas 9–11 (pocillos neutros)

/// Muestra plana de un color de datos con su filo fino.
struct LayerSwatchChip: View {
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
        shape.fill(color)
            .overlay(SwatchHairline(shape: shape))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Capa 9: swatches que se pueden aislar y clusters descartados o fusionados.
struct LabelsDetail: View {
    let stack: LayerStack
    @ObservedObject var model: LayersInspectorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SwatchWell(padding: Spacing.sm, cornerRadius: Radius.card) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(stack.swatches) { row in
                            let selected = model.isolatedSwatch == row.index
                            Button {
                                model.toggleIsolation(row.index)
                            } label: {
                                HStack(spacing: 6) {
                                    LayerSwatchChip(color: Color(swatch: row.swatch))
                                    Text("\(row.index + 1) · \(SubjectExplanation.count(row.pixels)) px")
                                        .textRole(.labelMD)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.wellText)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(selected ? Theme.wellFillAlt : Color.clear))
                                .overlay { if selected { WellSelectionRing(shape: Capsule()) } }
                                .frame(minHeight: Sizes.minTouch)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(row.index + 1), \(row.swatch.hex.uppercased()), \(row.pixels) píxeles")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("layers.swatch.\(row.index)")
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            if let isolated = model.isolatedSwatch {
                Text("Mostrando solo los píxeles del color \(isolated + 1). Tócalo otra vez para ver todos.")
                    .textRole(.bodySM)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if stack.clusters.isEmpty {
                Text("Ningún cluster se fusionó ni se descartó.")
                    .textRole(.bodySM)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Clusters que no llegaron tal cual a la paleta").textRole(.labelLG).foregroundStyle(.white)
                SwatchWell(padding: Spacing.md, cornerRadius: Radius.card) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(stack.clusters) { c in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                LayerSwatchChip(color: Color(rgb8: c.rgb.0, c.rgb.1, c.rgb.2))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.hex.uppercased()) · peso \(SubjectExplanation.percent(c.weight)) · \(SubjectExplanation.count(c.pixels)) px")
                                        .textRole(.labelMD)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.wellText)
                                    Text(c.reason)
                                        .textRole(.bodySM)
                                        .foregroundStyle(Theme.wellTextSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Capa 10: paleta con porcentajes y el color más cercano del diccionario, en un pocillo.
struct PaletteDetail: View {
    let rows: [SwatchRow]

    var body: some View {
        SwatchWell(padding: Spacing.md, cornerRadius: Radius.card) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                PaletteRibbon(colors: rows.map { PaletteColor(id: $0.index, swatch: $0.swatch, dictionary: nil) },
                              style: .weights, height: Sizes.weightBar, inWell: false)
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        LayerSwatchChip(color: Color(swatch: row.swatch), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.index + 1). \(row.swatch.hex.uppercased()) · \(SubjectExplanation.percent(row.swatch.weight)) · \(SubjectExplanation.count(row.pixels)) px")
                                .textRole(.labelMD)
                                .monospacedDigit()
                                .foregroundStyle(Theme.wellText)
                            HStack(spacing: Spacing.xs) {
                                if let near = PaletteColor(id: row.index, hex: row.nearestColorHex) {
                                    LayerSwatchChip(color: near.color, size: 12)
                                }
                                Text("Más cercano del diccionario: \(row.nearestColorName) (\(row.nearestColorHex.uppercased()), ΔE00 \(DesignFormat.score(row.nearestDeltaE)))")
                                    .textRole(.bodySM)
                                    .foregroundStyle(Theme.wellTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Capa 11: una combinación del top-3 y por qué tiene su score, en un pocillo.
struct ExplanationCardView: View {
    let card: ExplanationCard

    var body: some View {
        SwatchWell(padding: Spacing.md, cornerRadius: Radius.card) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text("\(card.rank)º")
                        .textRole(.labelLG)
                        .monospacedDigit()
                        .foregroundStyle(Theme.wellText)
                    PaletteRibbon(colors: card.comboHexes.enumerated().compactMap { PaletteColor(id: $0.offset, hex: $0.element) },
                                  style: .strip, height: 24, inWell: false)
                        .frame(width: 88)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(card.title).textRole(.cardTitle).foregroundStyle(Theme.wellText).lineLimit(2)
                        Text("Score \(DesignFormat.score(card.score))")
                            .textRole(.bodySM)
                            .monospacedDigit()
                            .foregroundStyle(Theme.wellTextSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: 4) {
                    GridRow {
                        Text("Color de la foto").textRole(.labelSM).foregroundStyle(Theme.wellTextSecondary)
                        Text("Más cercano de la combinación").textRole(.labelSM).foregroundStyle(Theme.wellTextSecondary)
                        Text("ΔE00").textRole(.labelSM).foregroundStyle(Theme.wellTextSecondary).gridColumnAlignment(.trailing)
                    }
                    ForEach(card.swatchLines) { line in
                        GridRow {
                            HStack(spacing: 4) {
                                chip(line.swatchHex)
                                Text("\(line.swatch + 1) · \(DesignFormat.percent(line.swatchWeight))")
                                    .textRole(.bodySM)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.wellText)
                            }
                            HStack(spacing: 4) {
                                chip(line.colorHex)
                                Text(line.colorName).textRole(.bodySM).foregroundStyle(Theme.wellText)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Text(DesignFormat.score(line.deltaE)).textRole(.bodySM).monospacedDigit().foregroundStyle(Theme.wellText)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ajuste \(DesignFormat.score(card.fitTerm)) · cobertura \(DesignFormat.score(card.coverageTerm)) · penalización \(DesignFormat.score(card.hypothesisPenalty))")
                        .textRole(.bodySM)
                        .monospacedDigit()
                        .foregroundStyle(Theme.wellText)
                    Text("Hipótesis: \(card.hypothesis)").textRole(.bodySM).foregroundStyle(Theme.wellText)
                    if !card.colorLines.isEmpty {
                        Text("Cobertura: " + card.colorLines.map { "\($0.colorName) → color \($0.nearestSwatch + 1) (\(DesignFormat.score($0.deltaE)))" }.joined(separator: " · "))
                            .textRole(.bodySM)
                            .foregroundStyle(Theme.wellTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(card.summary)
                    .textRole(.bodySM)
                    .foregroundStyle(Theme.wellTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("layers.explain.\(card.rank)")
    }

    private func chip(_ hex: String) -> some View {
        LayerSwatchChip(color: PaletteColor(id: 0, hex: hex)?.color ?? .clear, size: 14)
    }
}
