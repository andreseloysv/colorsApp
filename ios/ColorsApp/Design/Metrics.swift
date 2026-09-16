// Forma, espacio y elevación (docs/design/DESIGN_SYSTEM.md §3.1–§3.3).
// Radios tomados del ejemplo renderizado (Tailwind DEFAULT 4 / lg 8 / xl 12) y 24
// solo para hojas. Sombras «luz de día difusa» sobre la forma de fondo, nunca sobre
// el contenido; E3 (halo musgo + ámbar) jamás en elementos que contienen un swatch.
import SwiftUI

/// Espaciados (pt). 1 px del ejemplo = 1 pt.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 32
    /// Margen lateral de pantalla.
    static let margin: CGFloat = 16
    /// Hueco de cuadrícula (Rejilla, prendas, estudio).
    static let gutter: CGFloat = 12
    /// Extras de Tailwind: relleno vertical de chips (1.5), botones secundarios (2.5), CTA (3.5).
    static let chipVertical: CGFloat = 6
    static let buttonVertical: CGFloat = 10
    static let ctaVertical: CGFloat = 14
    /// Relleno mínimo del pocillo neutro (6 en la cuadrícula de la Rejilla).
    static let wellPadding: CGFloat = 8
    static let wellPaddingCompact: CGFloat = 6
    /// Separación entre segmentos de una tira de color (`swatchDivider`).
    static let swatchDivider: CGFloat = 2
}

/// Radios de esquina (estilo continuo).
enum Radius {
    /// Etiqueta pequeña («ΔE 2,3»).
    static let tag: CGFloat = 4
    /// Bloque de color, miniaturas, fichas, tiras, carriles interiores.
    static let block: CGFloat = 8
    /// Tarjetas, visor, pocillos de sección.
    static let card: CGFloat = 12
    /// Hojas (solo esquinas superiores).
    static let sheet: CGFloat = 24
}

/// Medidas recurrentes (§3.2).
enum Sizes {
    static let header: CGFloat = 64
    static let headerButton: CGFloat = 44
    static let brandMark: CGFloat = 32
    static let avatar: CGFloat = 32
    static let sourceIcon: CGFloat = 36
    static let viewfinderMaxHeight: CGFloat = 400
    static let droplet: CGFloat = 44
    static let garmentBlock: CGFloat = 64
    static let dayRibbon: CGFloat = 24
    static let extractRibbon: CGFloat = 12
    static let harvestStrip: CGFloat = 32
    static let weightBar: CGFloat = 16
    static let randomTile: CGFloat = 48
    static let gridStripes: CGFloat = 112
    static let pinBead: CGFloat = 24
    static let harvestThumb: CGFloat = 48
    static let minTouch: CGFloat = 44
    static let tabBar: CGFloat = 64
    static let profileBadge: CGFloat = 56
    /// Proporciones admitidas de la foto de una publicación (ancho / alto): 4:5 … 4:3.
    static let postAspectRange: ClosedRange<CGFloat> = (4.0 / 5.0)...(4.0 / 3.0)
}

/// Niveles de elevación (§3.3).
enum Elevation: Sendable, CaseIterable {
    /// E0: pocillos, chips, filas.
    case flat
    /// E1: tarjetas en reposo (publicación, rejilla, perfil, buscador).
    case rest
    /// E1+: tarjeta del día, aleatoria, cosechas.
    case restStrong
    /// E2: carpetas, fichas del estudio, botones secundarios.
    case small
    /// E3: CTA principal, toasts. Nunca en elementos con swatch.
    case floating
    /// E3 neutra: alfileres y etiquetas sobre la foto.
    case overPhoto
}

/// Aplica las sombras de un nivel. `neutral` = sombra negra (tarjetas cuyo fondo es un pocillo).
struct ElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let level: Elevation
    var neutral: Bool = false

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let tint: Color = (neutral || dark) ? .black : Theme.sepia
        switch level {
        case .flat:
            content
        case .rest:
            content
                .shadow(color: tint.opacity(dark ? 0.45 : 0.06), radius: 7, x: 0, y: 4)
                .shadow(color: tint.opacity(dark ? 0.0 : 0.04), radius: 1.5, x: 0, y: 1)
        case .restStrong:
            content
                .shadow(color: tint.opacity(dark ? 0.5 : 0.08), radius: 7, x: 0, y: 4)
                .shadow(color: tint.opacity(dark ? 0.0 : 0.05), radius: 1.5, x: 0, y: 1)
        case .small:
            content.shadow(color: tint.opacity(dark ? 0.35 : 0.06), radius: 4, x: 0, y: 2)
        case .floating:
            if dark || neutral {
                content.shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 14, x: 0, y: 12)
            } else {
                content
                    .shadow(color: Theme.mossGlow, radius: 14, x: 0, y: 12)
                    .shadow(color: Theme.amberGlowBase.opacity(0.10), radius: 6, x: 0, y: 4)
            }
        case .overPhoto:
            content.shadow(color: .black.opacity(dark ? 0.4 : 0.18), radius: 5, x: 0, y: 2)
        }
    }
}

/// Filo de luz superior (`inset 0 1px 1px rgba(255,255,255,0.7)`): trazo interior que se
/// apaga en el primer 12 % de la altura. Decorativo: no se pone sobre pocillos.
struct SunGlint<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let shape: S

    func body(content: Content) -> some View {
        content.overlay {
            shape
                .strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.10 : 0.7), .white.opacity(0)],
                                             startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)),
                              lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Sombras del nivel sobre esta vista (ponerlo en la forma de fondo).
    func elevation(_ level: Elevation, neutral: Bool = false) -> some View {
        modifier(ElevationModifier(level: level, neutral: neutral))
    }

    func sunGlint<S: InsettableShape>(_ shape: S) -> some View {
        modifier(SunGlint(shape: shape))
    }

    func sunGlint(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(SunGlint(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Fondo de tarjeta del marco: relleno + sombras en la forma + borde opcional + filo de luz.
    func solarCard(fill: Color = Theme.card, cornerRadius: CGFloat = Radius.card, elevation level: Elevation = .rest,
                   border: Color? = nil, glint: Bool = false) -> some View {
        modifier(SolarCardModifier(fill: fill, cornerRadius: cornerRadius, level: level, border: border, glint: glint))
    }
}

struct SolarCardModifier: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let fill: Color
    let cornerRadius: CGFloat
    let level: Elevation
    let border: Color?
    let glint: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(fill).elevation(level)
            }
            .overlay {
                if let border {
                    shape.strokeBorder(border, lineWidth: 1 / max(displayScale, 1)).allowsHitTesting(false)
                }
            }
            .overlay {
                if glint {
                    Color.clear.sunGlint(shape)
                }
            }
    }
}

/// Pulsación: escala 0,97 con muelle (sin escalas con «Reducir movimiento»).
struct SolarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.8),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SolarPressStyle {
    static var solarPress: SolarPressStyle { SolarPressStyle() }
}
