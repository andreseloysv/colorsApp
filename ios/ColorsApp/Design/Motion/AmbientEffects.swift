// Efectos ambientales del ejemplo como modificadores de SwiftUI, todos sobre
// `AmbientTimeline` (30 fps como máximo, pausa en segundo plano / fuera de pantalla,
// estado de reposo quieto con «Reducir movimiento»):
//   glowPulse()     tarjeta con halo ámbar ↔ verde azulado que respira + color de borde
//   glowCard()      el mismo halo, estático (clase de tarjeta con brillo del ejemplo)
//   solarSparkle()  giro 0→180→0°, escala 1→1,1 y resplandor ámbar 6→14 px en 12 s
//   spinning(_:)    `animate-spin` con duración (3 s toast, 6 s botón, 8 s lente, 25 s anillos)
//   pingDot()    `animate-ping` (escala ×2 y se apaga en el 75 % de 1 s)
//   pulse()         `animate-pulse` (opacidad 1 → 0,5 → 1 en 2 s)
//   shimmerSweep()  barrido de luz blanca al 30 % en 2,5 s recortado a la forma
// Zona neutra (DESIGN_SYSTEM.md §1.4): ninguno de estos modificadores se aplica a un
// pocillo, a un swatch ni a una tira de paleta; van en el marco (tarjetas, botones,
// iconos, puntos de estado, cabecera y pestañas).
import SwiftUI

// MARK: - Halo exterior

/// Sombras de color SOLO por fuera de la forma, como `box-shadow` de CSS (que no pinta
/// debajo de la caja): capas independientes y el interior recortado.
struct OuterGlow<S: Shape>: View {
    let shape: S
    let shadows: [ShadowSpec]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            ForEach(Array(shadows.map { $0.adapted(for: scheme) }.enumerated()), id: \.offset) { _, s in
                shape.fill(s.color.opacity(1).color)
                    .shadow(color: s.color.color, radius: s.radius, x: CGFloat(s.x), y: CGFloat(s.y))
            }
            shape.fill(Color.black).blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Tarjeta con halo que respira

struct GlowPulseModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var borderWidth: CGFloat = 1
    var clock: AnimationClock = MotionSpec.glowPulseClock

    /// Estado exacto de los keyframes (0 % / 50 % / 100 %, ease-in-out por tramo).
    static func state(at time: Double?, clock: AnimationClock = MotionSpec.glowPulseClock) -> GlowState {
        guard let time, let p = clock.progress(at: time) else { return MotionSpec.glowPulseA }
        return MotionSpec.glowPulse.value(at: p)
    }

    /// Peso del estado 50 % (0 = A, 1 = B) con la misma curva por tramo.
    static func weightB(at time: Double?, clock: AnimationClock = MotionSpec.glowPulseClock) -> Double {
        guard let time, let p = clock.progress(at: time) else { return 0 }
        return MotionSpec.glowPulseWeight.value(at: p)
    }

    func body(content: Content) -> some View {
        content
            .background {
                // Rendimiento: los dos halos (A y B) se rasterizan una vez y solo cambia su opacidad
                // (fundido cruzado con el peso de los keyframes); el desenfoque no se recalcula por fotograma.
                AmbientTimeline(frameInterval: MotionSpec.slowFrameInterval) { t in
                    let w = Self.weightB(at: t, clock: clock)
                    ZStack {
                        OuterGlow(shape: shape, shadows: [MotionSpec.glowPulseA.inner, MotionSpec.glowPulseA.outer])
                            .opacity(1 - w)
                        OuterGlow(shape: shape, shadows: [MotionSpec.glowPulseB.inner, MotionSpec.glowPulseB.outer])
                            .opacity(w)
                    }
                }
            }
            .overlay {
                AmbientTimeline(frameInterval: MotionSpec.slowFrameInterval) { t in
                    shape.strokeBorder(Self.state(at: t, clock: clock).border.color, lineWidth: borderWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Halo estático de tarjeta (`0 0 18px` ámbar 22 % + `0 0 28px` musgo 12 %, borde ámbar 25 %).
/// Con `pressed` (dentro de `PressScaleButtonStyle`) sube a `0 0 22px` ámbar 30 %.
struct GlowCardModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var state: GlowState = MotionSpec.glowCard
    var borderWidth: CGFloat = 1
    @Environment(\.solarButtonPressed) private var pressed

    func body(content: Content) -> some View {
        content
            .background {
                OuterGlow(shape: shape, shadows: pressed ? [MotionSpec.glowCardPressed, state.outer] : [state.inner, state.outer])
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: MotionSpec.Press.slowDuration), value: pressed)
            }
            .overlay {
                shape.strokeBorder(state.border.color, lineWidth: borderWidth).allowsHitTesting(false)
            }
    }
}

// MARK: - Destello solar

struct SolarSparkleModifier: ViewModifier {
    var clock: AnimationClock = MotionSpec.sparkleClock
    /// false = sin resplandor (solo giro y escala).
    var glow: Bool = true

    static func state(at time: Double?, clock: AnimationClock = MotionSpec.sparkleClock) -> SparkleState {
        guard let time, let p = clock.progress(at: time) else { return MotionSpec.sparkleRest }
        return MotionSpec.sparkle.value(at: p)
    }

    func body(content: Content) -> some View {
        AmbientTimeline(frameInterval: MotionSpec.slowFrameInterval) { t in
            let s = Self.state(at: t, clock: clock)
            content
                .shadow(color: glow ? s.shadow.color.color : .clear, radius: s.shadow.radius)
                .scaleEffect(s.scale)
                .rotationEffect(.degrees(s.rotation))
        }
    }
}

// MARK: - Giro, ping y pulso

struct SpinningModifier: ViewModifier {
    let duration: Double

    static func angle(at time: Double?, duration: Double) -> Double {
        guard let time, let p = AnimationClock(duration: duration).progress(at: time) else { return 0 }
        return MotionSpec.spinRotation.value(at: p)
    }

    func body(content: Content) -> some View {
        AmbientTimeline(frameInterval: MotionSpec.spinFrameInterval(duration: duration)) { t in
            content.rotationEffect(.degrees(Self.angle(at: t, duration: duration)))
        }
    }
}

struct PingModifier: ViewModifier {
    static func state(at time: Double?) -> ScaleOpacity {
        guard let time, let p = MotionSpec.pingClock.progress(at: time) else { return ScaleOpacity(scale: 1, opacity: 1) }
        return MotionSpec.ping.value(at: p)
    }

    func body(content: Content) -> some View {
        AmbientTimeline(frameInterval: 1 / MotionSpec.pingFramesPerSecond) { t in
            let s = Self.state(at: t)
            content.scaleEffect(s.scale).opacity(s.opacity)
        }
    }
}

struct PulseModifier: ViewModifier {
    static func opacity(at time: Double?) -> Double {
        guard let time, let p = MotionSpec.pulseClock.progress(at: time) else { return 1 }
        return MotionSpec.pulse.value(at: p)
    }

    func body(content: Content) -> some View {
        AmbientTimeline(frameInterval: MotionSpec.slowFrameInterval) { t in
            content.opacity(Self.opacity(at: t))
        }
    }
}

/// Punto de estado con ping. `keepsCore` deja un punto fijo debajo del que se expande
/// (legible aunque el ping esté apagado); false = exactamente `animate-ping` sobre el punto.
struct PingDot: View {
    var color: Color = TailwindColor.amber400.color
    /// `w-1.5 h-1.5` = 6 pt.
    var size: CGFloat = 6
    var keepsCore: Bool = true

    var body: some View {
        ZStack {
            if keepsCore {
                Circle().fill(color)
            }
            Circle().fill(color).pingDot()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Barrido de luz

struct ShimmerSweepModifier<S: Shape>: ViewModifier {
    let shape: S
    var peakOpacity: Double = MotionSpec.shimmerPeakOpacity
    var clock: AnimationClock = MotionSpec.shimmerClock

    /// Desplazamiento del barrido en fracciones del ancho (−1 … 1); nil = sin barrido.
    static func offset(at time: Double?, clock: AnimationClock = MotionSpec.shimmerClock) -> Double? {
        guard let time, let p = clock.progress(at: time) else { return nil }
        return MotionSpec.shimmerOffset.value(at: p)
    }

    func body(content: Content) -> some View {
        content.overlay {
            AmbientTimeline { t in
                if let x = Self.offset(at: t, clock: clock) {
                    GeometryReader { proxy in
                        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                               .init(color: .white.opacity(peakOpacity), location: 0.5),
                                               .init(color: .white.opacity(0), location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .offset(x: proxy.size.width * CGFloat(x))
                    }
                }
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - API

extension View {
    /// Halo que respira ámbar ↔ verde azulado con borde que cambia de color (4 s por ciclo).
    func glowPulse<S: InsettableShape>(_ shape: S) -> some View {
        modifier(GlowPulseModifier(shape: shape))
    }

    func glowPulse(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(GlowPulseModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Halo estático de tarjeta del ejemplo (sube al pulsar dentro de `PressScaleButtonStyle`).
    func glowCard(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(GlowCardModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func glowCard<S: InsettableShape>(_ shape: S, state: GlowState = MotionSpec.glowCard) -> some View {
        modifier(GlowCardModifier(shape: shape, state: state))
    }

    /// Destello solar: 12 s lineal, 0→180→0°, escala 1→1,1, resplandor ámbar 6→14 px.
    func solarSparkle(glow: Bool = true) -> some View {
        modifier(SolarSparkleModifier(glow: glow))
    }

    /// Giro continuo lineal (`animate-spin` con `animation-duration`).
    func spinning(duration: Double) -> some View {
        modifier(SpinningModifier(duration: duration))
    }

    /// `animate-ping` sobre esta vista (se expande ×2 y desaparece; quieta con «Reducir movimiento»).
    func pingDot() -> some View {
        modifier(PingModifier())
    }

    /// `animate-pulse` (opacidad 1 → 0,5 → 1, 2 s).
    func pulse() -> some View {
        modifier(PulseModifier())
    }

    /// Barrido de luz blanca (30 %) de izquierda a derecha cada 2,5 s, recortado a `shape`.
    func shimmerSweep<S: Shape>(_ shape: S, peakOpacity: Double = MotionSpec.shimmerPeakOpacity) -> some View {
        modifier(ShimmerSweepModifier(shape: shape, peakOpacity: peakOpacity))
    }

    func shimmerSweep() -> some View {
        modifier(ShimmerSweepModifier(shape: Capsule()))
    }
}
