// Valores EXACTOS de movimiento y luz del ejemplo del usuario
// (exampleDesign/stitch_solarpunk_palette_studio/*/code.html), traducidos a unidades
// de SwiftUI. Convenciones:
// - 1 px CSS = 1 pt. Unidades Tailwind: w-1.5 = 6, w-2 = 8, w-2.5 = 10, w-3.5 = 14…
// - Desenfoque de `box-shadow` / `drop-shadow` de B px → `.shadow(radius: B / 2)` (la
//   desviación típica de CSS es la mitad del desenfoque), como en Metrics.swift.
// - `filter: blur(σ px)` → `.blur(radius: σ)`.
// - Colores de Tailwind v3 en sRGB8 con su opacidad (`bg-amber-300/60` = #FCD34D al 60 %).
// Todo esto es decoración del MARCO: nunca se aplica dentro de un pocillo
// (docs/design/DESIGN_SYSTEM.md §1.4).
import CoreGraphics
import SwiftUI

// MARK: - Color y sombra

/// Color sRGB8 con alfa (0…1), interpolable en alfa premultiplicado como CSS.
struct MotionRGBA: MotionInterpolable, Hashable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Desde 0xRRGGBB.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF), alpha)
    }

    func opacity(_ alpha: Double) -> MotionRGBA { MotionRGBA(r, g, b, alpha) }

    var color: Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    static func lerp(_ x: MotionRGBA, _ y: MotionRGBA, _ t: Double) -> MotionRGBA {
        let a = Double.lerp(x.a, y.a, t)
        guard a > 0 else { return MotionRGBA(Double.lerp(x.r, y.r, t), Double.lerp(x.g, y.g, t), Double.lerp(x.b, y.b, t), 0) }
        func channel(_ cx: Double, _ cy: Double) -> Double { Double.lerp(cx * x.a, cy * y.a, t) / a }
        return MotionRGBA(channel(x.r, y.r), channel(x.g, y.g), channel(x.b, y.b), a)
    }
}

/// Paleta de Tailwind v3 que usa el ejemplo (solo la que aparece en code.html).
enum TailwindColor {
    static let amber200 = MotionRGBA(hex: 0xFDE68A)
    static let amber300 = MotionRGBA(hex: 0xFCD34D)
    static let amber400 = MotionRGBA(hex: 0xFBBF24)
    static let amber500 = MotionRGBA(hex: 0xF59E0B)
    static let yellow200 = MotionRGBA(hex: 0xFEF08A)
    static let yellow300 = MotionRGBA(hex: 0xFDE047)
    static let yellow500 = MotionRGBA(hex: 0xEAB308)
    static let teal300 = MotionRGBA(hex: 0x5EEAD4)
    static let teal400 = MotionRGBA(hex: 0x2DD4BF)
    static let emerald300 = MotionRGBA(hex: 0x6EE7B7)
    static let emerald400 = MotionRGBA(hex: 0x34D399)
    /// `rgba(45,90,60,…)`: musgo de los halos (primary-container).
    static let moss = MotionRGBA(45, 90, 60)
    /// `rgba(68,48,28,…)`: sepia de las sombras de reposo.
    static let sepia = MotionRGBA(68, 48, 28)
    /// `rgba(253,147,63,…)`: secondary-container del Extract.
    static let secondaryContainer = MotionRGBA(hex: 0xFD933F)
    /// `rgba(20,66,38,…)`: primary del Extract.
    static let primary = MotionRGBA(hex: 0x144226)
    /// `rgba(188,239,199,…)`: primary-fixed (halo de la pestaña activa).
    static let primaryFixed = MotionRGBA(hex: 0xBCEFC7)
}

/// Una capa de `box-shadow` / `drop-shadow` de CSS (sin `inset`).
struct ShadowSpec: MotionInterpolable, Hashable {
    let color: MotionRGBA
    /// Desenfoque CSS en px.
    let blur: Double
    var x: Double = 0
    var y: Double = 0

    init(_ color: MotionRGBA, blur: Double, x: Double = 0, y: Double = 0) {
        self.color = color
        self.blur = blur
        self.x = x
        self.y = y
    }

    /// Radio de `.shadow(radius:)` de SwiftUI.
    var radius: CGFloat { CGFloat(blur / 2) }

    /// «Solarpunk Night»: el halo musgo `rgba(45,90,60,…)` no se ve sobre tierra oscura; en oscuro se
    /// usa el musgo claro `#A1D2AC` con la misma opacidad (DESIGN_SYSTEM.md §1.3, `mossGlow`).
    func adapted(for scheme: ColorScheme) -> ShadowSpec {
        guard scheme == .dark, color.r == 45, color.g == 90, color.b == 60 else { return self }
        return ShadowSpec(MotionRGBA(hex: 0xA1D2AC, alpha: color.a), blur: blur, x: x, y: y)
    }

    static func lerp(_ a: ShadowSpec, _ b: ShadowSpec, _ t: Double) -> ShadowSpec {
        ShadowSpec(MotionRGBA.lerp(a.color, b.color, t), blur: Double.lerp(a.blur, b.blur, t),
                   x: Double.lerp(a.x, b.x, t), y: Double.lerp(a.y, b.y, t))
    }
}

/// Dos capas de sombra + color de borde (estado de keyframes de pulso / clase de tarjeta con brillo).
struct GlowState: MotionInterpolable, Hashable {
    let inner: ShadowSpec
    let outer: ShadowSpec
    let border: MotionRGBA

    static func lerp(_ a: GlowState, _ b: GlowState, _ t: Double) -> GlowState {
        GlowState(inner: .lerp(a.inner, b.inner, t), outer: .lerp(a.outer, b.outer, t), border: .lerp(a.border, b.border, t))
    }
}

/// Transformación + sombra de `solar-sparkle`.
struct SparkleState: MotionInterpolable, Hashable {
    let rotation: Double
    let scale: Double
    let shadow: ShadowSpec

    static func lerp(_ a: SparkleState, _ b: SparkleState, _ t: Double) -> SparkleState {
        SparkleState(rotation: .lerp(a.rotation, b.rotation, t), scale: .lerp(a.scale, b.scale, t), shadow: .lerp(a.shadow, b.shadow, t))
    }
}

/// Escala + opacidad (`animate-ping`).
struct ScaleOpacity: MotionInterpolable, Hashable {
    let scale: Double
    let opacity: Double

    static func lerp(_ a: ScaleOpacity, _ b: ScaleOpacity, _ t: Double) -> ScaleOpacity {
        ScaleOpacity(scale: .lerp(a.scale, b.scale, t), opacity: .lerp(a.opacity, b.opacity, t))
    }
}

// MARK: - Especificaciones

enum MotionSpec {
    /// Tope de fotogramas de todo lo ambiental: 30 fps.
    static let ambientFramesPerSecond: Double = 30
    static var ambientFrameInterval: Double { 1 / ambientFramesPerSecond }
    /// Efectos lentos (destello de 12 s, halo de 4 s, pulso de 2 s): 15 fps bastan
    /// (≤ 1,5° o ≤ 0,04 de opacidad por fotograma) y ahorran evaluaciones.
    static let slowFramesPerSecond: Double = 15
    static var slowFrameInterval: Double { 1 / slowFramesPerSecond }
    /// Ping (1 s, un punto de 6 pt que dobla su tamaño): 20 fps (≤ 0,5 pt por fotograma).
    static let pingFramesPerSecond: Double = 20
    /// Motas de luz: 20 fps. Recorren 120 pt en 6,5…9 s, o sea ≤ 0,9 pt por fotograma;
    /// a 30 fps no se veía mejor y era la capa ambiental más cara (5 sprites con halo
    /// y desenfoque a pantalla completa).
    static let moteFramesPerSecond: Double = 20
    static var moteFrameInterval: Double { 1 / moteFramesPerSecond }

    /// Intervalo para un giro de `duration` s: el menor número de fotogramas que mantiene
    /// el paso ≤ 4° (3 s → 30 fps, 8 s → 12 fps, 25 s → 10 fps), entre 10 y 30 fps.
    static func spinFrameInterval(duration: Double) -> Double {
        guard duration > 0 else { return ambientFrameInterval }
        let fps = min(ambientFramesPerSecond, max(10, ((360 / duration) / 4).rounded(.up)))
        return 1 / fps
    }
    /// Fundido que sustituye a escalas y desplazamientos con «Reducir movimiento».
    static let reducedFadeDuration: Double = 0.15

    // MARK: Motas de luz (keyframes de flotación + capa fija de partículas)

    /// Una mota: `absolute w-N h-N rounded-full bg-<color>/<alfa> blur-[σ] shadow-[0_0_Bpx_<hex>]`
    /// con `style="left: L%; bottom: B%; animation: <flotación> Ds infinite ease-out Rs"`.
    struct Mote: Sendable, Hashable, Identifiable {
        let id: Int
        /// Diámetro en pt.
        let size: CGFloat
        /// Relleno (color con su alfa de Tailwind).
        let fill: MotionRGBA
        /// `filter: blur()` en px (0 = sin filtro).
        let blur: CGFloat
        /// Halo `box-shadow 0 0 Bpx color`.
        let glow: ShadowSpec
        /// `left` en fracción del ancho de la capa.
        let left: CGFloat
        /// `bottom` en fracción del alto de la capa.
        let bottom: CGFloat
        let clock: AnimationClock

        /// Centro en reposo (sin desplazamiento) dentro de una capa de tamaño `size`.
        func restCenter(in canvas: CGSize) -> CGPoint {
            CGPoint(x: canvas.width * left + self.size / 2, y: canvas.height * (1 - bottom) - self.size / 2)
        }
    }

    /// Las cinco motas del Feed, en el orden del HTML.
    static let motes: [Mote] = [
        Mote(id: 0, size: 8, fill: TailwindColor.amber300.opacity(0.6), blur: 1,
             glow: ShadowSpec(TailwindColor.yellow300, blur: 10), left: 0.12, bottom: 0.15,
             clock: AnimationClock(duration: 7, delay: 0)),
        Mote(id: 1, size: 10, fill: TailwindColor.teal300.opacity(0.5), blur: 1,
             glow: ShadowSpec(TailwindColor.teal300, blur: 12), left: 0.78, bottom: 0.25,
             clock: AnimationClock(duration: 8.5, delay: 1.5)),
        Mote(id: 2, size: 6, fill: TailwindColor.amber200.opacity(0.7), blur: 0.5,
             glow: ShadowSpec(TailwindColor.yellow200, blur: 8), left: 0.45, bottom: 0.40,
             clock: AnimationClock(duration: 6.5, delay: 3)),
        Mote(id: 3, size: 8, fill: TailwindColor.emerald300.opacity(0.4), blur: 1,
             glow: ShadowSpec(TailwindColor.emerald300, blur: 10), left: 0.88, bottom: 0.65,
             clock: AnimationClock(duration: 9, delay: 2)),
        Mote(id: 4, size: 6, fill: TailwindColor.amber300.opacity(0.5), blur: 0,
             glow: ShadowSpec(TailwindColor.amber300, blur: 6), left: 0.28, bottom: 0.08,
             clock: AnimationClock(duration: 7.8, delay: 4.2)),
    ]

    /// Flotación: `transform` solo en 0 % y 100 % (un tramo ease-out en todo el ciclo).
    static let moteTranslation = CSSKeyframes<CGPoint>([(0, .zero), (1, CGPoint(x: 15, y: -120))], curve: .easeOut)
    /// Flotación: opacidad 0 → 0,8 (20 %) → 0,6 (80 %) → 0, ease-out por tramo.
    static let moteOpacity = CSSKeyframes<Double>([(0, 0), (0.2, 0.8), (0.8, 0.6), (1, 0)], curve: .easeOut)

    // MARK: Tarjeta con halo

    /// Clase de tarjeta con brillo: `0 0 18px rgba(234,179,8,0.22), 0 0 28px rgba(45,90,60,0.12)`, borde `rgba(234,179,8,0.25)`.
    static let glowCard = GlowState(inner: ShadowSpec(TailwindColor.yellow500.opacity(0.22), blur: 18),
                                    outer: ShadowSpec(TailwindColor.moss.opacity(0.12), blur: 28),
                                    border: TailwindColor.yellow500.opacity(0.25))
    /// `hover:shadow-[0_0_22px_rgba(234,179,8,0.3)]` de la publicación (se usa al pulsar).
    static let glowCardPressed = ShadowSpec(TailwindColor.yellow500.opacity(0.3), blur: 22)

    /// Keyframes de pulso 0 % / 100 %.
    static let glowPulseA = GlowState(inner: ShadowSpec(TailwindColor.amber500.opacity(0.25), blur: 16),
                                      outer: ShadowSpec(TailwindColor.moss.opacity(0.15), blur: 30),
                                      border: TailwindColor.yellow500.opacity(0.4))
    /// Keyframes de pulso 50 %.
    static let glowPulseB = GlowState(inner: ShadowSpec(TailwindColor.teal400.opacity(0.35), blur: 24),
                                      outer: ShadowSpec(TailwindColor.amber500.opacity(0.3), blur: 36),
                                      border: TailwindColor.teal300.opacity(0.5))
    /// El ejemplo declara los keyframes de pulso sin aplicarlo a ningún elemento (no hay duración ni curva en
    /// code.html). Se adopta 4 s ease-in-out por tramo: un ciclo de respiración lento.
    static let glowPulseClock = AnimationClock(duration: 4)
    static let glowPulse = CSSKeyframes<GlowState>([(0, glowPulseA), (0.5, glowPulseB), (1, glowPulseA)], curve: .easeInOut)
    /// Peso del estado 50 % en el ciclo (para el fundido cruzado de los dos halos rasterizados).
    static let glowPulseWeight = CSSKeyframes<Double>([(0, 0), (0.5, 1), (1, 0)], curve: .easeInOut)

    /// Clase de halo doble (halo verde azulado + ámbar, estático): `0 0 14px rgba(45,212,191,0.35), 0 0 22px rgba(245,158,11,0.25)`.
    static let tealAmberGlow = GlowState(inner: ShadowSpec(TailwindColor.teal400.opacity(0.35), blur: 14),
                                         outer: ShadowSpec(TailwindColor.amber500.opacity(0.25), blur: 22),
                                         border: TailwindColor.teal300.opacity(0))

    // MARK: Destello solar (`@keyframes solar-sparkle`, `.solar-spirit { animation: solar-sparkle 12s infinite linear }`)

    static let sparkleClock = AnimationClock(duration: 12)
    static let sparkleRest = SparkleState(rotation: 0, scale: 1, shadow: ShadowSpec(TailwindColor.amber500.opacity(0.6), blur: 6))
    static let sparklePeak = SparkleState(rotation: 180, scale: 1.1, shadow: ShadowSpec(TailwindColor.amber500.opacity(0.9), blur: 14))
    static let sparkle = CSSKeyframes<SparkleState>([(0, sparkleRest), (0.5, sparklePeak), (1, sparkleRest)], curve: .linear)
    /// Halo detrás del sol: `absolute inset-1 rounded-full bg-amber-400/20 blur-sm` (blur-sm = 4 px).
    static let sunHaloFill = TailwindColor.amber400.opacity(0.2)
    static let sunHaloBlur: CGFloat = 4

    // MARK: Giro (`animate-spin` = `spin 1s linear infinite`, `to { rotate(360deg) }`)

    enum Spin {
        /// Icono del toast (`auto_awesome`, `animation-duration: 3s`).
        static let toast: Double = 3
        /// Icono del botón de latón (`magic_button`, 6 s).
        static let brassButton: Double = 6
        /// Icono de la píldora de lente sobre la foto (`filter_vintage`, 8 s).
        static let lensChip: Double = 8
        /// Anillos de reloj de sol de la tarjeta del día (`animate-[spin_25s_linear_infinite]`).
        static let sunDialRings: Double = 25
        /// Rejilla: `animate-[spin_8s_linear_infinite]` y `animate-[spin_10s_linear_infinite]`.
        static let gridSlow: Double = 10
        /// Tailwind por defecto.
        static let tailwindDefault: Double = 1
    }

    static let spinRotation = CSSKeyframes<Double>([(0, 0), (1, 360)], curve: .linear)

    // MARK: Ping y pulso (Tailwind v3)

    /// `animate-ping`: `ping 1s cubic-bezier(0,0,0.2,1) infinite`, `75%, 100% { scale(2); opacity: 0 }`.
    static let pingClock = AnimationClock(duration: 1)
    static let ping = CSSKeyframes<ScaleOpacity>([(0, ScaleOpacity(scale: 1, opacity: 1)),
                                                   (0.75, ScaleOpacity(scale: 2, opacity: 0)),
                                                   (1, ScaleOpacity(scale: 2, opacity: 0))], curve: .tailwindPing)
    /// `animate-pulse`: `pulse 2s cubic-bezier(0.4,0,0.6,1) infinite`, `50% { opacity: .5 }`.
    static let pulseClock = AnimationClock(duration: 2)
    static let pulse = CSSKeyframes<Double>([(0, 1), (0.5, 0.5), (1, 1)], curve: .tailwindPulse)

    // MARK: Barrido de luz (`animate-[shimmer_2.5s_infinite]`)

    /// El ejemplo usa `shimmer` sin declarar sus `@keyframes`; se adopta el barrido estándar
    /// `-translate-x-full` → `translate-x-full` con la curva por defecto de CSS (`ease`).
    static let shimmerClock = AnimationClock(duration: 2.5)
    /// Desplazamiento en fracciones del ancho: −1 → 1.
    static let shimmerOffset = CSSKeyframes<Double>([(0, -1), (1, 1)], curve: .ease)
    /// `bg-gradient-to-r from-transparent via-white/30 to-transparent`.
    static let shimmerPeakOpacity: Double = 0.3

    // MARK: Pulsación (`active:scale-95`, `hover:-translate-y-1`, `transition-all`)

    enum Press {
        /// `active:scale-95` (chips, píldoras, iconos).
        static let scale: CGFloat = 0.95
        /// `active:scale-[0.98]` (botón de latón a todo el ancho) y `active:scale-98` (Jardín).
        static let wideScale: CGFloat = 0.98
        /// `group-active:scale-90` (gotas).
        static let dropletScale: CGFloat = 0.90
        /// `hover:-translate-y-1` / `group-hover:-translate-y-1`: 4 pt hacia arriba.
        static let lift: CGFloat = 4
        /// `hover:-translate-y-0.5` (Rejilla): 2 pt.
        static let smallLift: CGFloat = 2
        /// Transición por defecto de Tailwind: 150 ms `cubic-bezier(0.4, 0, 0.2, 1)`.
        static let duration: Double = 0.15
        /// `duration-300` (gotas y tarjetas).
        static let slowDuration: Double = 0.3
    }

    // MARK: Barras esmeriladas

    struct FrostedBar: Sendable, Hashable {
        /// Opacidad del tinte `surface` sobre el material (`bg-surface/85`).
        let tintOpacity: Double
        /// Sombra de color de la barra.
        let shadow: ShadowSpec
        /// Filo (`border-b` / `border-t`) ámbar.
        let hairline: MotionRGBA
    }

    /// Cabecera: `bg-surface/85 backdrop-blur-xl shadow-[0_1px_14px_rgba(234,179,8,0.1)] border-b border-amber-500/10`.
    static let header = FrostedBar(tintOpacity: 0.85, shadow: ShadowSpec(TailwindColor.yellow500.opacity(0.1), blur: 14, y: 1),
                                   hairline: TailwindColor.amber500.opacity(0.1))
    /// Barra de pestañas: `bg-surface/90 backdrop-blur-xl shadow-[0_-3px_16px_rgba(234,179,8,0.12)] border-t border-amber-500/15`.
    static let tabBar = FrostedBar(tintOpacity: 0.9, shadow: ShadowSpec(TailwindColor.yellow500.opacity(0.12), blur: 16, y: -3),
                                   hairline: TailwindColor.amber500.opacity(0.15))

    // MARK: Filo de luz (`shadow-[inset_0_1px_1px_rgba(255,255,255,0.7)]`)

    /// Opacidades del filo interior blanco que aparecen en los ejemplos (0,7 la común).
    enum Glint {
        static let standard: Double = 0.7
        static let strong: Double = 0.8
        static let soft: Double = 0.6
        static let faint: Double = 0.3
    }

    // MARK: Avatares con anillo

    /// Avatar de cabecera: `p-0.5 bg-secondary-fixed shadow-[0_0_12px_rgba(245,158,11,0.35)]` + `ring-2 ring-amber-300/60`
    /// + insignia `w-3.5 h-3.5 bg-secondary-container animate-pulse` con «✦» de 8 px.
    static let headerAvatarGlow = ShadowSpec(TailwindColor.amber500.opacity(0.35), blur: 12)
    static let headerAvatarRing = TailwindColor.amber300.opacity(0.6)
    /// Avatar de publicación: `w-9 h-9 ring-2 ring-amber-400/40` (o `ring-teal-400/40`).
    static let postAvatarRingAmber = TailwindColor.amber400.opacity(0.4)
    static let postAvatarRingTeal = TailwindColor.teal400.opacity(0.4)

    // MARK: Sombras cálidas con nombre

    /// Botón de latón: `shadow-[0_0_18px_rgba(234,179,8,0.4)]`, pulsado `0_0_24px_rgba(234,179,8,0.6)`, borde `amber-300/40`.
    static let brassButton = ShadowSpec(TailwindColor.yellow500.opacity(0.4), blur: 18)
    static let brassButtonPressed = ShadowSpec(TailwindColor.yellow500.opacity(0.6), blur: 24)
    static let brassButtonBorder = TailwindColor.amber300.opacity(0.4)
    /// Chip activo: `shadow-[0_0_12px_rgba(45,90,60,0.3)] border border-emerald-400/30`.
    static let activeChip = ShadowSpec(TailwindColor.moss.opacity(0.3), blur: 12)
    static let activeChipBorder = TailwindColor.emerald400.opacity(0.3)
    /// Píldora de lente: `shadow-[0_0_12px_rgba(245,158,11,0.3)] border border-amber-300/40`
    /// (variante `rgba(45,212,191,0.3)` / `teal-300/40`).
    static let lensChipAmber = ShadowSpec(TailwindColor.amber500.opacity(0.3), blur: 12)
    static let lensChipAmberBorder = TailwindColor.amber300.opacity(0.4)
    static let lensChipTeal = ShadowSpec(TailwindColor.teal400.opacity(0.3), blur: 12)
    static let lensChipTealBorder = TailwindColor.teal300.opacity(0.4)
    /// Botón de lupa sobre la foto: `bg-surface-container-lowest/85 backdrop-blur-md shadow-md border border-emerald-400/30`.
    static let photoButtonBorderEmerald = TailwindColor.emerald400.opacity(0.3)
    static let photoButtonBorderTeal = TailwindColor.teal400.opacity(0.3)
    /// Toast: `bg-inverse-surface/95 backdrop-blur-md shadow-[0_0_20px_rgba(245,158,11,0.4)] border border-amber-400/30`.
    static let toast = ShadowSpec(TailwindColor.amber500.opacity(0.4), blur: 20)
    static let toastBorder = TailwindColor.amber400.opacity(0.3)
    /// Logotipo de la cabecera: `drop-shadow-[0_0_6px_rgba(245,158,11,0.3)]`.
    static let logo = ShadowSpec(TailwindColor.amber500.opacity(0.3), blur: 6)
    /// CTA del Extract: `shadow-[0_4px_16px_rgba(20,66,38,0.35),0_0_20px_rgba(253,147,63,0.3)]`.
    static let extractCTA = [ShadowSpec(TailwindColor.primary.opacity(0.35), blur: 16, y: 4),
                             ShadowSpec(TailwindColor.secondaryContainer.opacity(0.3), blur: 20)]
    /// Pestaña activa: `shadow-[0_0_15px_rgba(188,239,199,0.85)]`.
    static let activeTab = ShadowSpec(TailwindColor.primaryFixed.opacity(0.85), blur: 15)
    /// Reposo E1 (sepia): `0 4px 16px -2px rgba(68,48,28,0.06), 0 1px 3px rgba(68,48,28,0.04)`.
    static let restSepia = [ShadowSpec(TailwindColor.sepia.opacity(0.06), blur: 16, y: 4),
                            ShadowSpec(TailwindColor.sepia.opacity(0.04), blur: 3, y: 1)]

    // MARK: Anillos de reloj de sol (tarjeta del día, `absolute -right-6 -top-6 w-36 h-36 opacity-60`)

    enum SunDial {
        static let size: CGFloat = 144
        static let offset: CGFloat = 24
        static let opacity: Double = 0.6
    }
}
