// Alfileres con etiqueta sobre la foto (docs/design/DESIGN_SYSTEM.md §4 n.º 14 y §5.2).
// La cuenta es un pocillo mínimo (anillo `wellFill` + filo `wellEdge`) con sombra
// neutra; la etiqueta es pergamino esmerilado. Sin halos del color ni pulsos.
// La posición sale del label map del motor (geometría de etiquetas, sin lógica de color).
import SwiftUI
import ColorEngine

/// Un alfiler: punto normalizado (0…1) en coordenadas de la imagen.
struct PhotoPin: Identifiable, Hashable, Sendable {
    let id: Int
    let position: CGPoint
    let color: PaletteColor
    /// «Black».
    let title: String
    /// «39 %».
    var detail: String?
}

struct PinOverlay: View {
    let pins: [PhotoPin]
    /// Tamaño en píxeles de la imagen mostrada (para calcular el rectángulo ajustado).
    let imageSize: CGSize
    var contentMode: ContentMode = .fit
    var selectedID: Int?
    var onSelect: ((PhotoPin) -> Void)?
    /// Pulsación larga: `true` al empezar a aislar, `false` al soltar.
    var onIsolate: ((PhotoPin, Bool) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let rect = Self.displayRect(imageSize: imageSize, in: geo.size, contentMode: contentMode)
            let placements = Self.labelPlacements(pins: pins, rect: rect, bounds: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(pins) { pin in
                    let p = CGPoint(x: rect.minX + pin.position.x * rect.width, y: rect.minY + pin.position.y * rect.height)
                    let placement = placements[pin.id] ?? LabelPlacement(above: true, dx: 0)
                    PinView(pin: pin, placement: placement, isSelected: pin.id == selectedID,
                            maxLabelWidth: min(geo.size.width - 24, 220))
                        .position(x: p.x, y: p.y)
                        .onTapGesture { onSelect?(pin) }
                        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 20) {
                        } onPressingChanged: { pressing in
                            onIsolate?(pin, pressing)
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
    }

    /// Rectángulo que ocupa una imagen de `imageSize` dentro de `container` con `contentMode`.
    nonisolated static func displayRect(imageSize: CGSize, in container: CGSize, contentMode: ContentMode) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let sx = container.width / imageSize.width
        let sy = container.height / imageSize.height
        let s = contentMode == .fit ? min(sx, sy) : max(sx, sy)
        let w = imageSize.width * s
        let h = imageSize.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    /// Colocación de la etiqueta de un alfiler respecto a su cuenta.
    struct LabelPlacement: Equatable, Sendable {
        var above: Bool
        /// Desplazamiento horizontal de la etiqueta (la cuenta no se mueve).
        var dx: CGFloat
    }

    /// Ancho estimado de una etiqueta (cuenta + nombre + peso en `label-sm`).
    nonisolated static func estimatedLabelWidth(_ pin: PhotoPin) -> CGFloat {
        let chars = pin.title.count + (pin.detail.map { $0.count + 1 } ?? 0)
        return 32 + CGFloat(chars) * 6.6
    }

    /// Etiqueta arriba si la cuenta está en la mitad inferior y abajo si no; si choca con otra
    /// cuenta o etiqueta prueba el otro lado y desplazamientos laterales, y se queda con la
    /// opción de menor solape. Las cuentas nunca se mueven (caen sobre la prenda).
    nonisolated static func labelPlacements(pins: [PhotoPin], rect: CGRect, bounds: CGSize? = nil) -> [Int: LabelPlacement] {
        let points = Dictionary(uniqueKeysWithValues: pins.map {
            ($0.id, CGPoint(x: rect.minX + $0.position.x * rect.width, y: rect.minY + $0.position.y * rect.height))
        })
        let beads = pins.map { pin -> CGRect in
            let p = points[pin.id]!
            return CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
        }
        let limit = CGRect(origin: .zero, size: bounds ?? CGSize(width: rect.maxX + rect.minX, height: rect.maxY + rect.minY))
        var labels: [CGRect] = []
        var result: [Int: LabelPlacement] = [:]
        for pin in pins.sorted(by: { $0.position.y < $1.position.y }) {
            let p = points[pin.id]!
            let w = estimatedLabelWidth(pin)
            let preferAbove = pin.position.y > 0.5
            var candidates: [LabelPlacement] = []
            for dx: CGFloat in [0, -w * 0.45, w * 0.45, -w * 0.9, w * 0.9] {
                candidates.append(LabelPlacement(above: preferAbove, dx: dx))
                candidates.append(LabelPlacement(above: !preferAbove, dx: dx))
            }
            func box(_ c: LabelPlacement) -> CGRect {
                CGRect(x: p.x + c.dx - w / 2, y: c.above ? p.y - 44 : p.y + 18, width: w, height: 26)
            }
            func overlap(_ c: LabelPlacement) -> CGFloat {
                let b = box(c)
                var area: CGFloat = 0
                for other in beads + labels {
                    let i = b.intersection(other)
                    if !i.isNull { area += i.width * i.height }
                }
                let inside = b.intersection(limit)
                area += b.width * b.height - (inside.isNull ? 0 : inside.width * inside.height)
                return area
            }
            let chosen = candidates.first(where: { overlap($0) == 0 }) ?? candidates.min(by: { overlap($0) < overlap($1) })!
            labels.append(box(chosen))
            result[pin.id] = chosen
        }
        return result
    }

    /// Posiciones normalizadas de los alfileres desde el label map del motor (§5.2): centroide
    /// de los píxeles de cada swatch, ajustado al píxel más cercano con esa etiqueta para que la
    /// cuenta caiga sobre la prenda aunque la región no sea convexa. Ignora `paletteLabelNone`
    /// y `paletteLabelDiscarded`. Clave = índice del swatch.
    nonisolated static func positions(labelMap: [UInt8], width: Int, height: Int, swatchCount: Int) -> [Int: CGPoint] {
        guard width > 0, height > 0, labelMap.count >= width * height, swatchCount > 0 else { return [:] }
        var sumX = [Double](repeating: 0, count: swatchCount)
        var sumY = [Double](repeating: 0, count: swatchCount)
        var count = [Int](repeating: 0, count: swatchCount)
        for y in 0..<height {
            for x in 0..<width {
                let label = labelMap[y * width + x]
                guard label != paletteLabelNone, label != paletteLabelDiscarded, Int(label) < swatchCount else { continue }
                sumX[Int(label)] += Double(x)
                sumY[Int(label)] += Double(y)
                count[Int(label)] += 1
            }
        }
        var out: [Int: CGPoint] = [:]
        for s in 0..<swatchCount where count[s] > 0 {
            let cx = sumX[s] / Double(count[s])
            let cy = sumY[s] / Double(count[s])
            var best = (d: Double.infinity, x: 0, y: 0)
            for y in 0..<height {
                for x in 0..<width where Int(labelMap[y * width + x]) == s {
                    let d = (Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)
                    if d < best.d { best = (d, x, y) }
                }
            }
            out[s] = CGPoint(x: (Double(best.x) + 0.5) / Double(width), y: (Double(best.y) + 0.5) / Double(height))
        }
        return out
    }
}

/// Cuenta + etiqueta de un alfiler.
private struct PinView: View {
    let pin: PhotoPin
    let placement: PinOverlay.LabelPlacement
    let isSelected: Bool
    let maxLabelWidth: CGFloat

    var body: some View {
        // La cuenta queda exactamente en el punto; la etiqueta se desplaza arriba o abajo.
        ZStack {
            label.offset(x: placement.dx, y: placement.above ? -31 : 31)
            SwatchBead(color: pin.color.color, size: Sizes.pinBead)
                .overlay { if isSelected { WellSelectionRing(shape: Circle()) } }
                .elevation(.overPhoto)
                .scaleEffect(isSelected ? 1.08 : 1)
        }
        .frame(minWidth: Sizes.minTouch, minHeight: Sizes.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([pin.title, pin.detail, pin.color.hex].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var label: some View {
        HStack(spacing: 5) {
            SwatchBead(color: pin.color.color, size: 12, ring: 2)
            Text(pin.title).textRole(.labelSM).foregroundStyle(Theme.onSurface).lineLimit(1)
            if let detail = pin.detail {
                Text(detail).textRole(.labelSM).monospacedDigit().foregroundStyle(Theme.onSurfaceVariant)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .parchmentFrost(Capsule())
        .elevation(.overPhoto)
        .frame(maxWidth: maxLabelWidth)
        .fixedSize()
    }
}
