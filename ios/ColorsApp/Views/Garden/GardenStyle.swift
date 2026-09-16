// Valores de estilo propios del Jardín, tomados literalmente de
// exampleDesign/stitch_solarpunk_palette_studio/my_garden_vault…/code.html
// (docs/design/FIDELITY.md §6): tipografía con tracking del ejemplo, sombras sepia y
// neutras de Tailwind, colores de acento de las fichas y luciérnagas de la tarjeta de
// perfil (M18). Todo es decoración del MARCO: nada de esto se aplica dentro de un pocillo
// (DESIGN_SYSTEM.md §1.4). Conversión: 1 px CSS = 1 pt; desenfoque B px → radio B / 2.
import SwiftUI

// MARK: - Tipografía

enum GardenType {
    /// `font-headline-sm tracking-tight`: Literata 18 medium, tracking −0,45.
    static let headlineTight = TextRole(id: "garden-headline-tight", family: .serif, weight: .medium, size: 18,
                                        lineHeight: 24, tracking: -0.45, textStyle: .headline)
    /// `font-label-md tracking-wide`: Plus Jakarta 12 semibold, tracking 0,3.
    static let labelWide = TextRole(id: "garden-label-wide", family: .sans, weight: .semibold, size: 12,
                                    lineHeight: 16, tracking: 0.3, textStyle: .caption)
    /// `text-[11px]` sin peso: Plus Jakarta 11 regular.
    static let micro = TextRole(id: "garden-micro", family: .sans, weight: .regular, size: 11,
                                lineHeight: 14, tracking: 0, textStyle: .caption2)
}

// MARK: - Sombras

/// Sombras del ejemplo como capas de `.shadow` (sin `spread`: SwiftUI no lo tiene, por eso las
/// que llevan `-Npx` bajan un poco su opacidad). En oscuro la sepia no se ve sobre tierra oscura:
/// negro con la opacidad de E1 del sistema de diseño.
enum GardenShadow {
    /// Tarjeta de perfil: `0 4px 16px -2px rgba(68,48,28,.06), 0 1px 3px rgba(68,48,28,.04)`.
    static let profile = [ShadowSpec(TailwindColor.sepia.opacity(0.06), blur: 16, y: 4),
                          ShadowSpec(TailwindColor.sepia.opacity(0.04), blur: 3, y: 1)]
    /// Cosecha: `0 4px 18px -2px rgba(68,48,28,.07)`.
    static let harvest = [ShadowSpec(TailwindColor.sepia.opacity(0.07), blur: 18, y: 4)]
    /// Ficha del estudio: `0 2px 8px rgba(68,48,28,.06)`.
    static let tile = [ShadowSpec(TailwindColor.sepia.opacity(0.06), blur: 8, y: 2)]
    /// Carpeta: `0 2px 8px -1px rgba(68,48,28,.06)`.
    static let folder = [ShadowSpec(TailwindColor.sepia.opacity(0.06), blur: 8, y: 2)]
    /// `shadow-sm`: `0 1px 2px rgba(0,0,0,.05)`.
    static let sm = [ShadowSpec(MotionRGBA(0, 0, 0, 0.05), blur: 2, y: 1)]
    /// `shadow-md`: `0 4px 6px -1px rgba(0,0,0,.1), 0 2px 4px -2px rgba(0,0,0,.1)`.
    static let md = [ShadowSpec(MotionRGBA(0, 0, 0, 0.08), blur: 6, y: 4), ShadowSpec(MotionRGBA(0, 0, 0, 0.07), blur: 4, y: 2)]
    /// `shadow-xl`: `0 20px 25px -5px rgba(0,0,0,.1), 0 8px 10px -6px rgba(0,0,0,.1)`.
    static let xl = [ShadowSpec(MotionRGBA(0, 0, 0, 0.08), blur: 25, y: 20), ShadowSpec(MotionRGBA(0, 0, 0, 0.07), blur: 10, y: 8)]
    /// Halo del anillo del retrato (clase de halo sin definir en code.html → L1 suave):
    /// `0 0 16px rgba(234,179,8,.22)` + `0 0 28px rgba(45,90,60,.12)`.
    static let portraitGlow = [ShadowSpec(TailwindColor.yellow500.opacity(0.22), blur: 16),
                               ShadowSpec(TailwindColor.moss.opacity(0.12), blur: 28)]
}

struct GardenShadowModifier: ViewModifier {
    /// Una o dos capas (las sombras del ejemplo no pasan de dos).
    let layers: [ShadowSpec]
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let a = layers.first
        let b = layers.count > 1 ? layers[1] : nil
        content
            .shadow(color: color(a), radius: a?.radius ?? 0, x: CGFloat(a?.x ?? 0), y: CGFloat(a?.y ?? 0))
            .shadow(color: color(b), radius: b?.radius ?? 0, x: CGFloat(b?.x ?? 0), y: CGFloat(b?.y ?? 0))
    }

    private func color(_ s: ShadowSpec?) -> Color {
        guard let s else { return .clear }
        return scheme == .dark ? .black.opacity(min(0.5, s.color.a * 6)) : s.color.color
    }
}

extension View {
    /// Sombras del ejemplo en la forma de fondo (opaca) de una tarjeta, ficha o píldora.
    func gardenShadow(_ layers: [ShadowSpec]) -> some View {
        modifier(GardenShadowModifier(layers: layers))
    }
}

// MARK: - Acentos de las fichas del estudio

/// Tono de una ficha del estudio (`primary-fixed`, `secondary-fixed`, `tertiary-fixed`,
/// `secondary-container/30`), con su halo `shadow-[0_0_10px_rgba(…,0.6)]`.
enum GardenAccent: Sendable, CaseIterable {
    case moss, amber, celadon, sun

    /// Disco del icono (fijo en claro; contenedor oscuro en «Solarpunk Night»).
    var disc: Color {
        switch self {
        case .moss: Color(light: 0xBCEFC7, dark: 0x224F32)
        case .amber: Color(light: 0xFFDCC6, dark: 0x713700)
        case .celadon: Color(light: 0xBDECDC, dark: 0x224E42)
        case .sun: Color(light: 0xFD933F, dark: 0x713700, lightOpacity: 0.3, darkOpacity: 0.75)
        }
    }

    /// Icono sobre el disco (`text-primary`, `text-secondary`, `text-tertiary`).
    var ink: Color {
        switch self {
        case .moss: Theme.primary
        case .amber, .sun: Theme.secondary
        case .celadon: Theme.tertiary
        }
    }

    /// Halo del disco.
    var discGlow: ShadowSpec {
        switch self {
        case .moss: ShadowSpec(MotionRGBA(188, 239, 199, 0.6), blur: 10)
        case .amber: ShadowSpec(MotionRGBA(255, 220, 198, 0.6), blur: 10)
        case .celadon: ShadowSpec(MotionRGBA(189, 236, 220, 0.6), blur: 10)
        case .sun: ShadowSpec(MotionRGBA(253, 147, 63, 0.5), blur: 10)
        }
    }

    /// Orbe de esquina (`bg-…-fixed/20 blur-md`; al pulsar `/40`), sin la opacidad.
    var orb: Color {
        switch self {
        case .moss: Color(light: 0xBCEFC7, dark: 0x2D5A3C)
        case .amber: Color(light: 0xFFDCC6, dark: 0x954A00)
        case .celadon: Color(light: 0xBDECDC, dark: 0x2D594C)
        case .sun: Color(light: 0xFD933F, dark: 0xFD933F)
        }
    }

    /// Filo al pulsar (`hover:border-primary/40`…).
    var pressedBorder: Color {
        switch self {
        case .moss: Theme.primary.opacity(0.4)
        case .amber: Theme.secondary.opacity(0.4)
        case .celadon: Theme.tertiary.opacity(0.4)
        case .sun: Color(light: 0xFD933F, dark: 0xFFB785, lightOpacity: 0.4, darkOpacity: 0.4)
        }
    }
}

// MARK: - Luciérnagas de la tarjeta de perfil (M18)

/// Una luciérnaga: `div.firefly.absolute.<anclas>.w-N.h-N.rounded-full.bg-<color>.shadow-[0_0_Bpx_<hex>]`
/// con `animation-delay`. La clase `firefly` no está definida en code.html: se implementa la
/// intención propuesta en FIDELITY.md M18 (4 s ease-in-out, deriva (3, −6) pt, opacidad .4 → 1 → .4).
struct GardenFirefly: Sendable, Hashable, Identifiable {
    let id: Int
    /// Diámetro en pt.
    let size: CGFloat
    let fill: MotionRGBA
    let glow: ShadowSpec
    /// Distancias a los bordes de la tarjeta (nil = sin ancla en ese eje).
    var top: CGFloat?
    var bottom: CGFloat?
    var left: CGFloat?
    var right: CGFloat?
    let clock: AnimationClock

    /// Centro en reposo dentro de una tarjeta de tamaño `canvas`.
    func restCenter(in canvas: CGSize) -> CGPoint {
        let x: CGFloat = if let left { left + size / 2 } else { canvas.width - (right ?? 0) - size / 2 }
        let y: CGFloat = if let top { top + size / 2 } else { canvas.height - (bottom ?? 0) - size / 2 }
        return CGPoint(x: x, y: y)
    }
}

enum GardenMotion {
    /// Personajes del retrato y luciérnagas: 20 fps (vaivén de ±6° en 2,6 s, bote de 3 pt en 2,2 s y
    /// deriva de 6 pt en 2 s se ven continuos) por debajo del tope ambiental de 30 fps.
    static let characterFrameInterval: Double = 1.0 / 20.0

    static let fireflyDrift = CSSKeyframes<CGPoint>([(0, .zero), (0.5, CGPoint(x: 3, y: -6)), (1, .zero)], curve: .easeInOut)
    static let fireflyOpacity = CSSKeyframes<Double>([(0, 0.4), (0.5, 1), (1, 0.4)], curve: .easeInOut)

    /// Las tres luciérnagas del ejemplo, en el orden del HTML.
    static let fireflies: [GardenFirefly] = [
        // top-3 right-16 w-2 h-2 bg-secondary-container shadow-[0_0_8px_#fd933f]
        GardenFirefly(id: 0, size: 8, fill: TailwindColor.secondaryContainer, glow: ShadowSpec(MotionRGBA(hex: 0xFD933F), blur: 8),
                      top: 12, right: 64, clock: AnimationClock(duration: 4)),
        // bottom-6 left-12 w-1.5 h-1.5 bg-primary-fixed shadow-[0_0_6px_#bcefc7], retraso 1,5 s
        GardenFirefly(id: 1, size: 6, fill: TailwindColor.primaryFixed, glow: ShadowSpec(MotionRGBA(hex: 0xBCEFC7), blur: 6),
                      bottom: 24, left: 48, clock: AnimationClock(duration: 4, delay: 1.5)),
        // top-10 left-2 w-2 h-2 bg-primary-fixed shadow-[0_0_7px_#a1d2ac], retraso 2,4 s
        GardenFirefly(id: 2, size: 8, fill: TailwindColor.primaryFixed, glow: ShadowSpec(MotionRGBA(hex: 0xA1D2AC), blur: 7),
                      top: 40, left: 8, clock: AnimationClock(duration: 4, delay: 2.4)),
    ]

    /// Desplazamiento y opacidad de una luciérnaga en `time` (nil = reposo quieto de «Reducir movimiento»).
    /// Durante el retraso inicial queda en su sitio con la opacidad del 0 %.
    static func firefly(_ f: GardenFirefly, at time: Double?) -> (offset: CGPoint, opacity: Double) {
        guard let time, let p = f.clock.progress(at: time) else { return (.zero, fireflyOpacity.value(at: 0)) }
        return (fireflyDrift.value(at: p), fireflyOpacity.value(at: p))
    }
}

/// Capa de luciérnagas (un solo `AmbientTimeline` para las tres; se pausa fuera de pantalla).
struct GardenFirefliesLayer: View {
    var fireflies: [GardenFirefly] = GardenMotion.fireflies

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            AmbientTimeline(frameInterval: GardenMotion.characterFrameInterval) { t in
                ZStack(alignment: .topLeading) {
                    ForEach(fireflies) { f in
                        let state = GardenMotion.firefly(f, at: t)
                        let c = f.restCenter(in: size)
                        ZStack {
                            OuterGlow(shape: Circle(), shadows: [f.glow])
                            Circle().fill(f.fill.color)
                        }
                        .frame(width: f.size, height: f.size)
                        .opacity(state.opacity)
                        .position(x: c.x + state.offset.x, y: c.y + state.offset.y)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
