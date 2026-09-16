// Materiales del marco (docs/design/DESIGN_SYSTEM.md §3.4): pergamino esmerilado
// para cabecera, HUD sobre la foto, etiquetas de alfiler y barra de pestañas, y los
// lavados difusos de fondo (§1.3). Nada de esto se pone dentro de un pocillo ni en
// celdas de listas largas (coste de desenfoque).
import SwiftUI

/// Pergamino esmerilado: `.ultraThinMaterial` + tinte cálido + filo de latón.
struct ParchmentFrost<S: InsettableShape>: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let shape: S
    var hairline: Bool = true

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.frostTint)
                if hairline {
                    shape.strokeBorder(Theme.brassHairline, lineWidth: 1 / max(displayScale, 1))
                }
            }
        }
    }
}

extension View {
    /// Fondo de pergamino esmerilado con la forma dada (por defecto rectángulo).
    func parchmentFrost<S: InsettableShape>(_ shape: S, hairline: Bool = true) -> some View {
        modifier(ParchmentFrost(shape: shape, hairline: hairline))
    }

    func parchmentFrost(hairline: Bool = true) -> some View {
        modifier(ParchmentFrost(shape: Rectangle(), hairline: hairline))
    }
}

/// Lavado difuso cálido o verde en una esquina de una tarjeta (a ≥ 16 pt de un pocillo).
struct SolarWash: View {
    enum Kind: Sendable { case warm, green }
    let kind: Kind
    var diameter: CGFloat = 144
    var blur: CGFloat = 40

    var body: some View {
        Circle()
            .fill(kind == .warm ? Theme.washWarm : Theme.washGreen)
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
