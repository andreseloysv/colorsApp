// Zona neutra de juicio de color (docs/design/DESIGN_SYSTEM.md §1.4): el pocillo
// y todo lo que pinta colores de datos. Reglas: fondo `wellFill` (blanco / #303030),
// filo `wellEdge` de 1 px físico, ≥ 8 pt de relleno, swatches planos con
// `swatchHairline`, selección con anillo neutro (sin brillos, sombras de color,
// degradados, desenfoques ni opacidad sobre el color).
import SwiftUI

/// Pocillo neutro que envuelve colores de datos.
struct SwatchWell<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    var padding: CGFloat
    var cornerRadius: CGFloat
    var fill: Color
    private let content: Content

    init(padding: CGFloat = Spacing.wellPadding, cornerRadius: CGFloat = Radius.card, fill: Color = Theme.wellFill,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1)).allowsHitTesting(false))
            // Las motas de luz (`lightMotes()`) no pasan por encima del pocillo.
            .neutralZone(cornerRadius: cornerRadius)
    }
}

/// Anillo de selección neutro: 2 pt `wellText` a 2 pt del elemento.
struct WellSelectionRing<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        shape.strokeBorder(Theme.wellText, lineWidth: 2).padding(-4).allowsHitTesting(false)
    }
}

/// Borde fino de un swatch (distingue un blanco roto del pocillo).
struct SwatchHairline<S: InsettableShape>: View {
    @Environment(\.displayScale) private var displayScale
    let shape: S
    var body: some View {
        shape.strokeBorder(Theme.swatchHairline, lineWidth: 1 / max(displayScale, 1)).allowsHitTesting(false)
    }
}

/// Relleno de combinación bloqueada: gris neutro rayado + candado.
struct LockedSwatchPlaceholder: View {
    var cornerRadius: CGFloat = Radius.block
    var showsLock: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Theme.wellPlaceholder)
            Canvas { context, size in
                var path = Path()
                let step: CGFloat = 10
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += step
                }
                context.stroke(path, with: .color(Theme.wellPlaceholderStripe), lineWidth: 4)
            }
            .clipShape(shape)
            if showsLock {
                Image(systemName: "lock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.wellTextSecondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Combinación bloqueada")
    }
}

/// Cuenta de color con anillo `wellFill` de 2 pt y filo `wellEdge` (pocillo mínimo sobre foto o marco).
struct SwatchBead: View {
    @Environment(\.displayScale) private var displayScale
    let color: Color
    var size: CGFloat = Sizes.pinBead
    var ring: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().fill(Theme.wellFill)
            Circle().fill(color).padding(ring)
            SwatchHairline(shape: Circle().inset(by: ring))
            Circle().strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1))
        }
        .frame(width: size, height: size)
        .neutralZone(cornerRadius: size / 2)
        .accessibilityHidden(true)
    }
}

/// Micro-píldora: cuenta + nombre + hex sobre `wellFillAlt` neutro.
struct MicroColorPill: View {
    @Environment(\.displayScale) private var displayScale
    let color: PaletteColor
    var showsHex: Bool = true
    var showsWeight: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            SwatchBead(color: color.color, size: 14, ring: 2)
            if let name = color.name {
                Text(name)
                    .textRole(.labelSM)
                    .foregroundStyle(Theme.wellText)
                    .lineLimit(1)
            }
            if showsHex {
                Text(color.hex)
                    .textRole(.hex)
                    .foregroundStyle(Theme.wellTextSecondary)
                    .lineLimit(1)
            }
            if showsWeight, let w = color.weight {
                Text(DesignFormat.percent(w))
                    .textRole(.labelSM)
                    .monospacedDigit()
                    .foregroundStyle(Theme.wellTextSecondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Capsule().fill(Theme.wellFillAlt))
        .overlay(Capsule().strokeBorder(Theme.wellEdge, lineWidth: 1 / max(displayScale, 1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([color.name, color.hex].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Tira de paleta dentro de un pocillo (§4 n.º 8). Estilos: partes iguales, proporcional
/// al peso, fichas separadas, franjas verticales y gotas con rótulos.
struct PaletteRibbon: View {
    enum Style: Sendable, Equatable {
        /// Partes iguales (tarjeta del día, combinación ganadora).
        case strip
        /// Proporcional a `weight` (cinta de Extraer, barra del Jardín).
        case weights
        /// Fichas separadas 6 pt (tarjeta aleatoria).
        case tiles
        /// Franjas verticales (tarjeta de la Rejilla).
        case stripes
        /// Círculos de 44 pt con nombre, hex y peso opcionales (Feed, cosechas).
        case droplets(names: Bool = true, hex: Bool = true, weights: Bool = false)
    }

    let colors: [PaletteColor]
    var style: Style = .strip
    /// Alto de la tira (ignorado en `.droplets`, que usa `dropletSize`).
    var height: CGFloat = Sizes.dayRibbon
    var dropletSize: CGFloat = Sizes.droplet
    /// Muestra el relleno rayado de bloqueada en lugar de los colores.
    var locked: Bool = false
    /// Índice (posición en `colors`) seleccionado.
    var selection: Int?
    /// false si el padre ya es un `SwatchWell` (no se anida otro pocillo).
    var inWell: Bool = true
    var wellPadding: CGFloat = Spacing.wellPadding
    var wellCornerRadius: CGFloat = Radius.block
    var onTap: ((PaletteColor) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if inWell {
            SwatchWell(padding: wellPadding, cornerRadius: wellCornerRadius) { content }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if locked || colors.isEmpty {
            LockedSwatchPlaceholder(cornerRadius: segmentRadius, showsLock: locked)
                .frame(height: resolvedHeight)
        } else {
            switch style {
            case .strip, .stripes:
                equalSegments
            case .weights:
                weightedSegments
            case .tiles:
                tiles
            case .droplets(let names, let hex, let weights):
                droplets(names: names, hex: hex, weights: weights)
            }
        }
    }

    private var resolvedHeight: CGFloat {
        if case .droplets = style { return dropletSize }
        return height
    }

    private var segmentRadius: CGFloat {
        switch style {
        case .weights: height / 2
        case .strip: min(Radius.block, height / 2)
        default: Radius.block
        }
    }

    private var equalSegments: some View {
        let shape = RoundedRectangle(cornerRadius: segmentRadius, style: .continuous)
        return HStack(spacing: Spacing.swatchDivider) {
            ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                segment(c, index: i, shape: Rectangle())
            }
        }
        .frame(height: height)
        .clipShape(shape)
        .overlay(selectionOverlayForStrip)
    }

    private var weightedSegments: some View {
        let total = max(colors.reduce(0) { $0 + max(0, $1.weight ?? 0) }, .leastNonzeroMagnitude)
        let shape = Capsule()
        return GeometryReader { geo in
            let available = max(0, geo.size.width - Spacing.swatchDivider * CGFloat(max(colors.count - 1, 0)))
            HStack(spacing: Spacing.swatchDivider) {
                ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                    segment(c, index: i, shape: Rectangle())
                        .frame(width: max(1, available * CGFloat(max(0, c.weight ?? 0) / total)))
                }
            }
        }
        .frame(height: height)
        .clipShape(shape)
    }

    private var tiles: some View {
        HStack(spacing: Spacing.wellPaddingCompact) {
            ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                segment(c, index: i, shape: shape)
                    .clipShape(shape)
                    .overlay { if selection == i { WellSelectionRing(shape: shape) } }
                    .scaleEffect(selection == i && !reduceMotion ? 1.04 : 1)
                    .offset(y: selection == i ? -2 : 0)
            }
        }
        .frame(height: height)
    }

    private func droplets(names: Bool, hex: Bool, weights: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                let content = VStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(c.color)
                        .overlay(SwatchHairline(shape: Circle()))
                        .overlay { if selection == i { WellSelectionRing(shape: Circle()) } }
                        .frame(width: dropletSize, height: dropletSize)
                        .scaleEffect(selection == i && !reduceMotion ? 1.04 : 1)
                        .offset(y: selection == i ? -2 : 0)
                        .padding(.top, 2)
                    if names, let name = c.name {
                        Text(name)
                            .textRole(.labelSM)
                            .foregroundStyle(Theme.wellText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    if hex {
                        Text(c.hex)
                            .textRole(.hex)
                            .foregroundStyle(Theme.wellTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if weights, let w = c.weight {
                        Text(DesignFormat.percent(w))
                            .textRole(.labelSM)
                            .monospacedDigit()
                            .foregroundStyle(Theme.wellTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                tappable(content, color: c, index: i)
            }
        }
    }

    @ViewBuilder
    private func segment<S: InsettableShape>(_ c: PaletteColor, index: Int, shape: S) -> some View {
        let fill = shape.fill(c.color).overlay(SwatchHairline(shape: shape))
        tappable(fill, color: c, index: index)
    }

    @ViewBuilder
    private func tappable<V: View>(_ view: V, color c: PaletteColor, index: Int) -> some View {
        let label = DesignFormat.accessibilityLabel(c, position: index, total: colors.count)
        if let onTap {
            Button { onTap(c) } label: { view.contentShape(Rectangle()) }
                .buttonStyle(.solarPress)
                .accessibilityLabel(label)
                .accessibilityHint("Copia el hex")
        } else {
            view.accessibilityElement().accessibilityLabel(label)
        }
    }

    /// En tiras de partes iguales la selección se marca con un anillo alrededor del segmento.
    @ViewBuilder private var selectionOverlayForStrip: some View {
        if let selection, colors.indices.contains(selection) {
            GeometryReader { geo in
                let n = CGFloat(colors.count)
                let w = (geo.size.width - Spacing.swatchDivider * (n - 1)) / n
                let x = CGFloat(selection) * (w + Spacing.swatchDivider)
                Rectangle()
                    .strokeBorder(Theme.wellText, lineWidth: 2)
                    .frame(width: w, height: geo.size.height)
                    .offset(x: x)
            }
            .allowsHitTesting(false)
        }
    }
}
