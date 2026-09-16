// Logotipo, wordmark y conjunto de cabecera de ChromaSol (DESIGN_SYSTEM.md §3.6 y §4 n.º 1,
// con el aspecto de las capturas del ejemplo: emblema de 32 pt con resplandor ámbar
// `drop-shadow(0 0 6px rgba(245,158,11,0.3))`, «ChromaSol» en Literata `headline-sm` musgo
// con tracking −0,45, el punto ámbar `bg-amber-400` con `animate-ping` y debajo la etiqueta
// de sección `label-sm` ámbar en mayúsculas con tracking amplio).
import SwiftUI

/// Emblema animable. `size` < 56 usa el estilo compacto salvo que se indique otro.
struct ChromaSolLogo: View {
    var size: CGFloat = Sizes.brandMark
    var style: ChromaSolEmblemStyle?
    /// Destello solar opcional (12 s, 180°, drop-shadow 6 → 14 px). Con Reduce Motion, quieto.
    var animated: Bool = false
    /// Resplandor ámbar del marco del logotipo (como la cabecera del Feed del ejemplo).
    var glow: Bool = true

    var body: some View {
        BrandMotionClock(animated: animated) { time, reduceMotion in
            ChromaSolEmblem(style: resolvedStyle,
                            sun: BrandMotion.sparkle(at: time, animated: animated, reduceMotion: reduceMotion),
                            glow: animated && !reduceMotion)
                .frame(width: size, height: size)
                .shadow(color: Color(brand: 0xF59E0B, opacity: glow ? 0.3 : 0), radius: glow ? 3 : 0)
        }
        .accessibilityHidden(true)
    }

    var resolvedStyle: ChromaSolEmblemStyle { style ?? (size < 56 ? .compact : .full) }
}

/// Punto ámbar del wordmark: punto fijo `amber-400` y anillo de `animate-ping` detrás.
struct BrandPingDot: View {
    var diameter: CGFloat = 6
    var color: Color = Color(brand: 0xFBBF24)
    var animated: Bool = true

    var body: some View {
        BrandMotionClock(animated: animated) { time, reduceMotion in
            let ping = animated ? BrandMotion.wordmarkPing(at: time, reduceMotion: reduceMotion) : (scale: 1.0, opacity: 0.0)
            ZStack {
                Circle().fill(color.opacity(ping.opacity)).scaleEffect(ping.scale)
                Circle().fill(color)
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityHidden(true)
    }
}

enum BrandWordmarkSize: Sendable {
    /// Cabecera: Literata 18 medium, punto de 6 pt, etiqueta 11 pt.
    case header
    /// Portada, «Acerca de», galería: Literata 34 semibold, punto de 10 pt, etiqueta 14 pt.
    case display

    var nameRole: TextRole {
        switch self {
        case .header: .brand
        case .display: TextRole(id: "brand-display", family: .serif, weight: .semibold, size: 34, lineHeight: 40,
                                tracking: -0.68, textStyle: .largeTitle)
        }
    }

    var labelRole: TextRole {
        switch self {
        case .header: .overline
        case .display: TextRole(id: "brand-display-label", family: .sans, weight: .bold, size: 14, lineHeight: 18,
                                tracking: 2.2, textStyle: .subheadline, uppercase: true)
        }
    }

    var dot: CGFloat { self == .header ? 6 : 10 }
    var logo: CGFloat { self == .header ? Sizes.brandMark : 72 }
    var spacing: CGFloat { self == .header ? Spacing.sm : Spacing.md }
}

/// «ChromaSol •» y la etiqueta de sección debajo («FEED», «EXTRAER», «REJILLA», «JARDÍN»).
struct ChromaSolWordmark: View {
    /// Etiqueta de sección; nil la oculta.
    var section: String?
    var size: BrandWordmarkSize = .header
    /// Punto ámbar con `animate-ping` (el ejemplo lo muestra en el Feed).
    var showsDot: Bool = true
    var animated: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: size == .header ? 2 : 4) {
            HStack(alignment: .center, spacing: size == .header ? 4 : 6) {
                Text(AppBrand.name)
                    .textRole(size.nameRole)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                if showsDot {
                    BrandPingDot(diameter: size.dot, animated: animated)
                }
            }
            if let section, !(size == .header && dynamicTypeSize.isAccessibilitySize) {
                Text(section)
                    .textRole(size.labelRole)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.map { "\(AppBrand.name), \($0.capitalized(with: Locale(identifier: "es_ES")))" } ?? AppBrand.name)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Logotipo + wordmark, listo para la cabecera (`AppHeader`) o una portada.
struct ChromaSolLockup: View {
    var section: String?
    var size: BrandWordmarkSize = .header
    var showsDot: Bool = true
    /// Punto con ping y (en `.display`) destello del sol. Pasar false en pestañas ocultas.
    var animated: Bool = true

    var body: some View {
        HStack(spacing: size.spacing) {
            ChromaSolLogo(size: size.logo, animated: animated && size == .display)
            ChromaSolWordmark(section: section, size: size, showsDot: showsDot, animated: animated)
        }
    }
}
