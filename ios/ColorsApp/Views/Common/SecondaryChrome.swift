// Marco solarpunk de las pantallas secundarias (docs/design/FIDELITY.md §7.5): Ajustes,
// «Acerca de», licencias y el flujo de escaneo del carrete. El ejemplo del usuario no dibuja
// ninguna de estas pantallas, así que se toma su vocabulario de las cuatro que sí dibuja:
//   - cabecera `h-16 px-margin bg-surface/85 backdrop-blur-xl` con el logotipo ChromaSol, el
//     wordmark con su punto ámbar y el rótulo de sección (`FrostedHeaderBackground`);
//   - motas de luz de pantalla, que nunca pisan un pocillo (`.lightMotes()` respeta las
//     zonas neutras y se para con Reducir movimiento, fuera de pantalla y en reposo);
//   - tarjetas de sección con el halo de tarjeta del ejemplo (`0 0 18px` ámbar 22 % + `0 0 28px`
//     musgo 12 %, filo ámbar 25 %), orbe difuso en la esquina (`blur-md` del «Export Studio»
//     del Jardín) e insignia circular de tono con su rótulo en versales.
// Sin colores de datos: estas piezas son marco (§1.4 de DESIGN_SYSTEM.md).
import SwiftUI

// MARK: - Cabecera

/// Cabecera de una pantalla secundaria: pergamino esmerilado con filo ámbar, botón de volver
/// o cerrar, logotipo + «ChromaSol» con el rótulo de sección y, opcionalmente, algo a la derecha.
struct SecondaryHeader<Trailing: View>: View {
    /// Qué botón lleva a la izquierda.
    enum Leading: Sendable, Equatable {
        /// Flecha de volver (pila de navegación).
        case back
        /// Aspa de cerrar (hoja modal).
        case close
        /// Sin botón.
        case none

        var symbol: String? {
            switch self {
            case .back: "chevron.left"
            case .close: "xmark"
            case .none: nil
            }
        }

        var label: String {
            switch self {
            case .back: "Volver"
            case .close, .none: "Cerrar"
            }
        }
    }

    /// Rótulo de sección bajo el wordmark («AJUSTES», «ACERCA DE»…).
    let section: String
    var leading: Leading = .back
    /// Punto ámbar con ping junto al wordmark (como la cabecera del Feed del ejemplo).
    var showsDot: Bool = true
    var onLeading: (() -> Void)?
    var identifier: String?
    /// Identificador de accesibilidad del botón izquierdo (por defecto `<identifier>.leading`).
    var leadingIdentifier: String?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let symbol = leading.symbol {
                Button {
                    if let onLeading { onLeading() } else { dismiss() }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel(leading.label)
                .accessibilityIdentifier(leadingIdentifier ?? identifier.map { "\($0).leading" } ?? "")
                .padding(.leading, -Spacing.md)
            }
            ChromaSolLogo(size: Sizes.brandMark)
            ChromaSolWordmark(section: section, showsDot: showsDot, animated: true)
            Spacer(minLength: Spacing.sm)
            trailing()
        }
        .padding(.horizontal, Spacing.margin)
        .frame(minHeight: Sizes.header)
        .frame(maxWidth: .infinity)
        // Como una barra de navegación: crece con Dynamic Type hasta AX1.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background { FrostedHeaderBackground() }
        .accessibilityIdentifier(identifier ?? "")
    }
}

extension SecondaryHeader where Trailing == EmptyView {
    init(section: String, leading: Leading = .back, showsDot: Bool = true,
         onLeading: (() -> Void)? = nil, identifier: String? = nil, leadingIdentifier: String? = nil) {
        self.init(section: section, leading: leading, showsDot: showsDot, onLeading: onLeading,
                  identifier: identifier, leadingIdentifier: leadingIdentifier, trailing: { EmptyView() })
    }
}

// MARK: - Ambiente

/// Pergamino + motas de luz de una pantalla secundaria. Se pone en el `ScrollView`, antes de
/// la cabecera, para que las motas queden por debajo de la barra (como en el ejemplo).
struct SecondaryAmbience: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface.ignoresSafeArea())
            .lightMotes()
    }
}

extension View {
    /// Ver `SecondaryAmbience`.
    func secondaryAmbience() -> some View {
        modifier(SecondaryAmbience())
    }
}

// MARK: - Tarjeta de sección

/// Orbe difuso de esquina del ejemplo (`absolute -right-2 -top-2 w-10 h-10 rounded-full
/// bg-*/20 blur-md`), escalado a la tarjeta de sección.
struct SectionOrb: View {
    var tone: Tone = .moss
    var diameter: CGFloat = 88
    var blur: CGFloat = 24

    var body: some View {
        Circle()
            .fill(tone.badgeFill.opacity(0.42))
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Insignia circular de sección con el resplandor del ejemplo
/// (`w-8 h-8 rounded-full bg-* shadow-[0_0_10px_...]`).
struct SectionBadge: View {
    let systemImage: String
    var tone: Tone = .moss
    var diameter: CGFloat = 30
    /// Icono con pulso (2 s) del ejemplo; false = quieto.
    var pulses: Bool = false

    var body: some View {
        Circle()
            .fill(tone.badgeFill)
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: diameter * 0.47, weight: .semibold))
                    .foregroundStyle(tone.onBadge)
                    .modifier(SectionBadgePulse(active: pulses))
            }
            .warmShadow(tone == .amber ? .headerAvatar : .activeChip, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct SectionBadgePulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.pulse() } else { content }
    }
}

// MARK: - Atajos de depuración

#if DEBUG
/// Atajos de las pantallas secundarias para capturas (solo DEBUG):
/// `-uiScreen jardin -uiGardenPage acerca -uiAjustesPage licencias` abre Jardín › Ajustes ›
/// Acerca de › Licencias de fuentes; `-uiAjustesPage licencia-texto` sigue hasta el texto OFL.
enum SecondaryLaunch {
    static let pageArgument = "-uiAjustesPage"

    static var page: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: pageArgument), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
