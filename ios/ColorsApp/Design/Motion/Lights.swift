// Luces del marco: anillos de avatar con halo, sombras cálidas con nombre, filo de luz
// interior exacto, píldora de lente sobre la foto, botón esmerilado sobre la foto,
// halo del sol, insignia con destello y anillos de reloj de sol. Valores de MotionSpec.
// Zona neutra: nada de esto se pone dentro de un pocillo ni junto a un swatch.
import SwiftUI

// MARK: - Sombras cálidas

/// Sombras de color con nombre, tomadas literalmente del ejemplo.
enum WarmShadow: Sendable, CaseIterable {
    /// Tarjeta con brillo: `0 0 18px` ámbar 22 % + `0 0 28px` musgo 12 % (pulsada: `0 0 22px` ámbar 30 %).
    case glowCard
    /// Botón de latón: `0 0 18px` ámbar 40 % (pulsado `0 0 24px` 60 %).
    case brassButton
    /// Chip activo: `0 0 12px` musgo 30 %.
    case activeChip
    /// Píldora de lente: `0 0 12px` ámbar 30 %.
    case lensChipAmber
    /// Píldora de lente verde azulada: `0 0 12px` rgba(45,212,191,0.3).
    case lensChipTeal
    /// Toast: `0 0 20px` ámbar 40 %.
    case toast
    /// Logotipo: `drop-shadow 0 0 6px` ámbar 30 %.
    case logo
    /// Avatar de cabecera: `0 0 12px` ámbar 35 %.
    case headerAvatar
    /// Pestaña activa: `0 0 15px` rgba(188,239,199,0.85).
    case activeTab
    /// CTA del Extract: `0 4px 16px` musgo 35 % + `0 0 20px` naranja 30 %.
    case extractCTA
    /// Reposo sepia E1: `0 4px 16px -2px` 6 % + `0 1px 3px` 4 %.
    case restSepia

    var layers: [ShadowSpec] {
        switch self {
        case .glowCard: [MotionSpec.glowCard.inner, MotionSpec.glowCard.outer]
        case .brassButton: [MotionSpec.brassButton]
        case .activeChip: [MotionSpec.activeChip]
        case .lensChipAmber: [MotionSpec.lensChipAmber]
        case .lensChipTeal: [MotionSpec.lensChipTeal]
        case .toast: [MotionSpec.toast]
        case .logo: [MotionSpec.logo]
        case .headerAvatar: [MotionSpec.headerAvatarGlow]
        case .activeTab: [MotionSpec.activeTab]
        case .extractCTA: MotionSpec.extractCTA
        case .restSepia: MotionSpec.restSepia
        }
    }

    /// Capas al pulsar (el `hover:shadow-…` del ejemplo); nil = iguales.
    var pressedLayers: [ShadowSpec]? {
        switch self {
        case .glowCard: [MotionSpec.glowCardPressed, MotionSpec.glowCard.outer]
        case .brassButton: [MotionSpec.brassButtonPressed]
        default: nil
        }
    }
}

struct WarmShadowModifier<S: Shape>: ViewModifier {
    let preset: WarmShadow
    let shape: S
    @Environment(\.solarButtonPressed) private var pressed

    func body(content: Content) -> some View {
        content.background {
            OuterGlow(shape: shape, shadows: pressed ? (preset.pressedLayers ?? preset.layers) : preset.layers)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.duration), value: pressed)
        }
    }
}

extension View {
    /// Sombra cálida SOLO por fuera de `shape` (capas independientes, como `box-shadow`).
    func warmShadow<S: Shape>(_ preset: WarmShadow, in shape: S) -> some View {
        modifier(WarmShadowModifier(preset: preset, shape: shape))
    }

    /// Resplandor que sigue el contorno del contenido (`drop-shadow`, p. ej. logotipo o icono).
    func warmDropShadow(_ preset: WarmShadow = .logo) -> some View {
        let s = preset.layers.first ?? MotionSpec.logo
        return shadow(color: s.color.color, radius: s.radius, x: CGFloat(s.x), y: CGFloat(s.y))
    }
}

// MARK: - Filo de luz interior exacto

/// `shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]`: sombra interior blanca desplazada 1 pt
/// hacia abajo con 1 px de desenfoque: un filo de luz en el borde superior interno.
/// (El `SunGlint` de Metrics.swift es la versión en degradado; esta reproduce la sombra.)
struct InsetSunGlint<S: Shape>: ViewModifier {
    let shape: S
    var opacity: Double = MotionSpec.Glint.standard
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let rect = CGRect(origin: .zero, size: proxy.size)
                Path { p in
                    p.addRect(rect.insetBy(dx: -8, dy: -8))
                    p.addPath(shape.path(in: rect))
                }
                .fill(Color.white.opacity(scheme == .dark ? opacity * 0.2 : opacity), style: FillStyle(eoFill: true))
                .offset(y: 1)
                .blur(radius: 0.5)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func insetSunGlint<S: Shape>(_ shape: S, opacity: Double = MotionSpec.Glint.standard) -> some View {
        modifier(InsetSunGlint(shape: shape, opacity: opacity))
    }
}

// MARK: - Anillos de avatar

struct GlowRingModifier: ViewModifier {
    enum Style: Sendable, Hashable {
        /// Avatar de cabecera: fondo `secondary-fixed` 2 pt, halo ámbar 12 px 35 %, anillo `amber-300/60` 2 pt.
        case header
        /// Avatar de publicación: anillo `amber-400/40` 2 pt sobre `secondary-fixed`.
        case postAmber
        /// Avatar de publicación: anillo `teal-400/40` 2 pt sobre `tertiary-fixed`.
        case postTeal
    }

    let style: Style
    /// Insignia «✦» que late (`animate-pulse`) en la esquina superior derecha (solo cabecera).
    var sparkleBadge: Bool = false

    private var ringColor: Color {
        switch style {
        case .header: MotionSpec.headerAvatarRing.color
        case .postAmber: MotionSpec.postAvatarRingAmber.color
        case .postTeal: MotionSpec.postAvatarRingTeal.color
        }
    }

    private var plate: Color {
        style == .postTeal ? Theme.tertiaryFixed : Theme.secondaryFixed
    }

    func body(content: Content) -> some View {
        content
            .clipShape(Circle())
            .padding(2)
            .background(Circle().fill(plate))
            .overlay(Circle().strokeBorder(ringColor, lineWidth: 2).allowsHitTesting(false))
            .background {
                if style == .header {
                    OuterGlow(shape: Circle(), shadows: [MotionSpec.headerAvatarGlow])
                }
            }
            .overlay(alignment: .topTrailing) {
                if sparkleBadge {
                    SparkleBadge().offset(x: 2, y: -2)
                }
            }
    }
}

extension View {
    /// Anillo con halo para avatares y círculos de marca (el contenido se recorta en círculo).
    func glowRing(_ style: GlowRingModifier.Style = .header, sparkleBadge: Bool = false) -> some View {
        modifier(GlowRingModifier(style: style, sparkleBadge: sparkleBadge))
    }
}

/// Insignia de 14 pt `secondary-container` con «✦» de 8 pt, `shadow-md` y `animate-pulse`.
struct SparkleBadge: View {
    var body: some View {
        Circle()
            .fill(Theme.secondaryContainer)
            .frame(width: 14, height: 14)
            .overlay {
                // `text-on-secondary` del ejemplo; en oscuro el tono 90 para que el destello se vea.
                Text("✦").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(light: 0xFFFFFF, dark: 0xFFDCC6))
            }
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 4)
            .pulse()
            .accessibilityHidden(true)
    }
}

// MARK: - Sol

/// Halo detrás del sol de la cabecera: `absolute inset-1 rounded-full bg-amber-400/20 blur-sm`.
struct SunHalo: View {
    var body: some View {
        Circle()
            .fill(MotionSpec.sunHaloFill.color)
            .padding(4)
            .blur(radius: MotionSpec.sunHaloBlur)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Anillos de reloj de sol que giran detrás del rótulo de la tarjeta del día
/// (144 pt, opacidad 0,6, 25 s por vuelta; `-right-6 -top-6` en el ejemplo). Va en el FONDO de la
/// tarjeta: puede pasar por detrás de un pocillo (opaco), nunca por encima.
struct SunDialRings: View {
    var size: CGFloat = MotionSpec.SunDial.size

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 100
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (50 - r) * s, y: (50 - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            let secondary = GraphicsContext.Shading.color(Theme.secondary)
            context.stroke(circle(42), with: secondary, style: StrokeStyle(lineWidth: 1.5 * s, dash: [4 * s, 6 * s]))
            context.stroke(circle(30), with: .color(TailwindColor.teal300.opacity(0.6).color),
                           style: StrokeStyle(lineWidth: 1 * s, dash: [8 * s, 4 * s]))
            context.stroke(circle(22), with: secondary, lineWidth: 1 * s)
            var ticks = Path()
            for (a, b) in [(CGPoint(x: 50, y: 6), CGPoint(x: 50, y: 18)), (CGPoint(x: 50, y: 82), CGPoint(x: 50, y: 94)),
                           (CGPoint(x: 6, y: 50), CGPoint(x: 18, y: 50)), (CGPoint(x: 82, y: 50), CGPoint(x: 94, y: 50))] {
                ticks.move(to: CGPoint(x: a.x * s, y: a.y * s))
                ticks.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
            }
            context.stroke(ticks, with: secondary, lineWidth: 2 * s)
            context.fill(circle(3), with: .color(TailwindColor.amber500.color))
        }
        .frame(width: size, height: size)
        .spinning(duration: MotionSpec.Spin.sunDialRings)
        .opacity(MotionSpec.SunDial.opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Sobre la foto

/// Píldora esmerilada sobre la foto con icono que gira (8 s): `bottom-3 left-3 px-2.5 py-1
/// rounded-full bg-surface-container-lowest/90 backdrop-blur-md shadow-[0_0_12px_…0.3]
/// border border-amber-300/40` + icono `text-secondary 14px animate-spin 8s` + `label-sm` semibold.
struct SunbeamLensChip: View {
    enum LensTone: Sendable { case amber, teal }

    let title: String
    var systemImage: String = "camera.filters"
    var tone: LensTone = .amber

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .spinning(duration: MotionSpec.Spin.lensChip)
                .accessibilityHidden(true)
            Text(title)
                .textRole(.labelSM, weight: .semibold)
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Theme.containerLowest.opacity(0.9))
            }
        }
        .overlay(Capsule().strokeBorder(tone == .amber ? MotionSpec.lensChipAmberBorder.color : MotionSpec.lensChipTealBorder.color,
                                        lineWidth: 1))
        .warmShadow(tone == .amber ? .lensChipAmber : .lensChipTeal, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }
}

/// Botón redondo esmerilado de 32 pt sobre la foto (`top-3 right-3 w-8 h-8
/// bg-surface-container-lowest/85 backdrop-blur-md shadow-md text-primary border border-emerald-400/30`).
struct FrostedPhotoButton: View {
    enum EdgeTone: Sendable { case emerald, teal }

    let systemImage: String
    let accessibilityLabel: String
    var tone: EdgeTone = .emerald
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(Theme.containerLowest.opacity(0.85))
                    }
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
                }
                .overlay(Circle().strokeBorder(tone == .emerald ? MotionSpec.photoButtonBorderEmerald.color
                                                                : MotionSpec.photoButtonBorderTeal.color, lineWidth: 1))
                .frame(width: Sizes.minTouch, height: Sizes.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Zona neutra para las luces

/// Rectángulo de un pocillo en el espacio de la capa de luces.
struct NeutralZoneRect: Sendable, Hashable {
    let rect: CGRect
    let cornerRadius: CGFloat
}

struct NeutralZoneAnchor {
    let bounds: Anchor<CGRect>
    let cornerRadius: CGFloat
}

struct NeutralZoneKey: PreferenceKey {
    static var defaultValue: [NeutralZoneAnchor] { [] }

    static func reduce(value: inout [NeutralZoneAnchor], nextValue: () -> [NeutralZoneAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marca esta vista como zona neutra: las motas de luz (`lightMotes()`) no pasan por encima.
    func neutralZone(cornerRadius: CGFloat = 0) -> some View {
        transformAnchorPreference(key: NeutralZoneKey.self, value: .bounds) { value, anchor in
            value.append(NeutralZoneAnchor(bounds: anchor, cornerRadius: cornerRadius))
        }
    }
}
