// Alfileres vivos del visor de Extraer (docs/design/FIDELITY.md §4 E12–E16; ejemplo
// `clothing_extractor…/code.html`, `.garment-pin`). Misma geometría que `PinOverlay`
// (rectángulo ajustado, etiquetas sin colisiones) con las luces del ejemplo:
//   - aro detrás de la cuenta con `animate-ping` (1 s) según la luminancia L* del color (motor):
//     claro (L* > 80) sin ping y con halo estático crema; oscuro (L* < 35) aro verde claro;
//     resto, aro naranja (trazo en el dominante, relleno en los demás);
//   - halo melocotón con resplandor naranja detrás del color dominante (mayor peso);
//   - cuenta de 24 pt (pocillo mínimo neutro) con halo de SU color por fuera y glifo de
//     «punto de muestra» (aro discontinuo + punto, ≤ 40 % del disco);
//   - etiqueta esmerilada `bg-surface/95` con filo por tono, punto con halo, nombre, peso y «✦»/«✧»;
//   - al pulsar, la cuenta crece a 1,25 (150 ms `cubic-bezier(.4,0,.2,1)`).
// Las luces se apagan con la máscara visible, mientras se aísla un color y en el alfiler
// seleccionado. El aro y los halos van SOBRE LA FOTO, nunca dentro de un pocillo.
import SwiftUI
import ColorEngine

/// Tono de un color para elegir la variante de luz del alfiler (L* del motor, sin lógica de color aquí).
enum ExtractPinTone: Sendable, Equatable {
    case light, mid, dark

    /// L* > 80 claro; L* < 35 oscuro.
    nonisolated static func of(r: UInt8, g: UInt8, b: UInt8) -> ExtractPinTone {
        let l = srgbToLab(r: r, g: g, b: b).L
        if l > 80 { return .light }
        if l < 35 { return .dark }
        return .mid
    }

    nonisolated static func of(_ color: PaletteColor) -> ExtractPinTone { of(r: color.r, g: color.g, b: color.b) }

    /// Destello decorativo de la etiqueta y de la tarjeta: «✧» en claros, «✦» en el resto.
    var sparkle: String { self == .light ? "✧" : "✦" }
}

struct ExtractPinOverlay: View {
    let pins: [PhotoPin]
    let imageSize: CGSize
    var selectedID: Int?
    /// Color de mayor peso (halo melocotón).
    var dominantID: Int?
    /// false = sin aros, halos ni glifo animado (máscara visible o color aislado).
    var lightsOn: Bool = true
    var onSelect: ((PhotoPin) -> Void)?
    var onIsolate: ((PhotoPin, Bool) -> Void)?

    @State private var pressedID: Int?

    /// Centro de cada alfiler (pt) dentro de un contenedor de `size`.
    nonisolated static func centers(pins: [PhotoPin], imageSize: CGSize, in size: CGSize) -> [CGPoint] {
        let rect = PinOverlay.displayRect(imageSize: imageSize, in: size, contentMode: .fit)
        return pins.map { CGPoint(x: rect.minX + $0.position.x * rect.width, y: rect.minY + $0.position.y * rect.height) }
    }

    var body: some View {
        GeometryReader { geo in
            let rect = PinOverlay.displayRect(imageSize: imageSize, in: geo.size, contentMode: .fit)
            let placements = PinOverlay.labelPlacements(pins: pins, rect: rect, bounds: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(pins) { pin in
                    let p = CGPoint(x: rect.minX + pin.position.x * rect.width, y: rect.minY + pin.position.y * rect.height)
                    ExtractPinView(pin: pin,
                                   placement: placements[pin.id] ?? PinOverlay.LabelPlacement(above: true, dx: 0),
                                   isSelected: pin.id == selectedID,
                                   isDominant: pin.id == dominantID,
                                   isPressed: pin.id == pressedID,
                                   lightsOn: lightsOn && pin.id != selectedID,
                                   maxLabelWidth: min(geo.size.width - 24, 230))
                        .position(x: p.x, y: p.y)
                        .onTapGesture { onSelect?(pin) }
                        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 20) {
                        } onPressingChanged: { pressing in
                            pressedID = pressing ? pin.id : (pressedID == pin.id ? nil : pressedID)
                            onIsolate?(pin, pressing)
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ExtractPinView: View {
    let pin: PhotoPin
    let placement: PinOverlay.LabelPlacement
    var isSelected = false
    var isDominant = false
    var isPressed = false
    var lightsOn = true
    var maxLabelWidth: CGFloat = 230

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    private var tone: ExtractPinTone { ExtractPinTone.of(pin.color) }

    var body: some View {
        let reduce = systemReduceMotion || forcedReduceMotion
        ZStack {
            label.offset(x: placement.dx, y: placement.above ? -27 : 27)
            ZStack {
                if lightsOn { ring }
                if lightsOn && isDominant { dominantHalo }
                bead
            }
            .scaleEffect(reduce ? 1 : (isPressed ? 1.25 : (isSelected ? 1.08 : 1)))
            .animation(reduce ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                              : .timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.duration), value: isPressed)
        }
        .frame(minWidth: Sizes.minTouch, minHeight: Sizes.minTouch)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: MotionSpec.reducedFadeDuration), value: lightsOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([pin.title, pin.detail, pin.color.hex].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Luces sobre la foto

    /// Aro con ping (E12). Claro: halo estático `bg-surface-container/60 shadow-[0_0_10px_rgba(232,222,200,0.9)]`.
    @ViewBuilder private var ring: some View {
        switch tone {
        case .light:
            Circle()
                .fill(Theme.container.opacity(0.6))
                .frame(width: 28, height: 28)
                .background { OuterGlow(shape: Circle(), shadows: [ShadowSpec(MotionRGBA(232, 222, 200, 0.9), blur: 10)]) }
        case .dark:
            Circle()
                .strokeBorder(Color(brand: 0xBCEFC7, opacity: 0.7), lineWidth: 1)
                .frame(width: 32, height: 32)
                .pingDot()
                .opacity(0.6)
        case .mid:
            Group {
                if isDominant {
                    Circle().strokeBorder(Color(brand: 0xFD933F, opacity: 0.6), lineWidth: 1).frame(width: 36, height: 36)
                } else {
                    Circle().fill(Color(brand: 0xFD933F, opacity: 0.3)).frame(width: 32, height: 32)
                }
            }
            .pingDot()
            .opacity(0.6)
        }
    }

    /// Halo del dominante (E13): `w-8 h-8 bg-secondary-fixed/40 shadow-[0_0_14px_rgba(253,147,63,0.7)]`.
    private var dominantHalo: some View {
        Circle()
            .fill(Color(brand: 0xFFDCC6, opacity: 0.4))
            .frame(width: 32, height: 32)
            .background { OuterGlow(shape: Circle(), shadows: [ShadowSpec(TailwindColor.secondaryContainer.opacity(0.7), blur: 14)]) }
    }

    /// Cuenta (E14–E15): pocillo mínimo con halo de su color por fuera y glifo de muestra.
    private var bead: some View {
        SwatchBead(color: pin.color.color, size: Sizes.pinBead)
            .background {
                if lightsOn {
                    OuterGlow(shape: Circle(),
                              shadows: [ShadowSpec(MotionRGBA(Double(pin.color.r), Double(pin.color.g), Double(pin.color.b), 0.8), blur: 10)])
                }
            }
            .overlay { SamplePointGlyph(tone: tone).frame(width: 8, height: 8) }
            .overlay { if isSelected { WellSelectionRing(shape: Circle()) } }
            .compositingGroup()
            .shadow(color: .black.opacity(lightsOn ? 0.10 : 0.18), radius: lightsOn ? 2 : 5, x: 0, y: lightsOn ? 1 : 2)
    }

    // MARK: Etiqueta

    /// E16: `bg-surface/95 backdrop-blur-md px-2.5 py-0.5 rounded-full shadow-[0_2px_10px_rgba(0,0,0,0.18)]
    /// border border-secondary-fixed/60` (claro `surface-variant`, oscuro `primary-fixed-dim`).
    private var label: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pin.color.color)
                .frame(width: 8, height: 8)
                .overlay(SwatchHairline(shape: Circle()))
                .background {
                    if lightsOn && tone != .light {
                        OuterGlow(shape: Circle(),
                                  shadows: [ShadowSpec(MotionRGBA(Double(pin.color.r), Double(pin.color.g), Double(pin.color.b)), blur: 6)])
                    }
                }
            Text(pin.title).textRole(.labelSM, weight: .semibold).foregroundStyle(Theme.onSurface).lineLimit(1)
            if let detail = pin.detail {
                Text(detail).textRole(.labelSM, weight: .semibold).monospacedDigit().foregroundStyle(Theme.onSurfaceVariant)
            }
            Text(tone.sparkle)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tone == .mid ? Theme.secondary : Theme.primary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Theme.surface.opacity(0.95))
            }
        }
        .overlay(Capsule().strokeBorder(labelEdge, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
        .frame(maxWidth: maxLabelWidth)
        .fixedSize()
    }

    private var labelEdge: Color {
        switch tone {
        case .light: Theme.surfaceVariant
        case .dark: Theme.primaryFixedDim
        case .mid: Color(brand: 0xFFDCC6, opacity: 0.6)
        }
    }
}

/// Glifo de «punto de muestra» (E15): aro discontinuo `2 1` y punto central; blanco sobre colores
/// medios u oscuros, musgo al 45 % sobre claros. Estático (a 8 pt la flotación no se percibe).
struct SamplePointGlyph: View {
    let tone: ExtractPinTone

    var body: some View {
        let ink = tone == .light ? Color(brand: 0x144226, opacity: 0.45) : Color.white.opacity(0.9)
        Canvas { ctx, size in
            let s = size.width / 12
            var c = ctx
            c.scaleBy(x: s, y: s)
            c.stroke(Path(ellipseIn: CGRect(x: 1.5, y: 1.5, width: 9, height: 9)), with: .color(ink),
                     style: StrokeStyle(lineWidth: 1.2, dash: [2, 1]))
            c.fill(Path(ellipseIn: CGRect(x: 4.2, y: 4.2, width: 3.6, height: 3.6)), with: .color(ink))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
