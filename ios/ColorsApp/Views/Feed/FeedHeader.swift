// Cabecera luminosa del Feed (docs/design/FIDELITY.md §3 F2–F9; ejemplo
// `solar_feed…/code.html`, `<header>`): pergamino esmerilado al 85 % con sombra ámbar
// `0 1px 14px rgba(234,179,8,0.1)` y filo inferior ámbar al 10 %; emblema ChromaSol de 32 pt
// con resplandor ámbar, «ChromaSol» con punto que late (`animate-ping`) y «FEED» debajo;
// a la derecha el sol con carita (dibujo original: rayos-pétalo que hacen el destello solar
// de 12 s mientras la cara queda derecha) sobre su halo `bg-amber-400/20 blur-sm`, y el
// avatar local (brote en maceta) con aro `ring-2 ring-amber-300/60`, halo ámbar y la
// insignia «✦» que late SOLO si hay combinaciones nuevas desde la última visita al Jardín.
// Acciones reales: el sol abre Extraer («Analizar una foto») y el avatar, el Jardín.
// Movimiento: todo pasa por AmbientTimeline / BrandMotionClock (≤ 30 fps, pausa fuera de
// pantalla, en segundo plano y en la pestaña oculta; quieto con «Reducir movimiento»).
import SwiftUI

struct FeedHeader: View {
    /// Movimiento de marca activo (la pestaña Feed está a la vista).
    var animated: Bool = true
    /// Combinaciones desbloqueadas desde la última visita al Jardín (0 = sin insignia).
    var newUnlocks: Int = 0
    var onAnalyze: () -> Void
    var onGarden: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // `img.h-8 … drop-shadow-[0_0_6px_rgba(245,158,11,0.3)]` + `gap-space-sm`.
            ChromaSolLogo(size: Sizes.brandMark, animated: false, glow: true)
            ChromaSolWordmark(section: "Feed", showsDot: true, animated: animated)
                .accessibilityIdentifier("feed.header.brand")
            Spacer(minLength: Spacing.sm)
            HStack(spacing: Spacing.xs) {
                FeedSunSpiritButton(action: onAnalyze)
                FeedGardenAvatarButton(newUnlocks: newUnlocks, action: onGarden)
            }
        }
        .padding(.horizontal, Spacing.margin)
        .frame(minHeight: Sizes.header)
        .frame(maxWidth: .infinity)
        // Crece con Dynamic Type hasta AX1, como una barra de navegación.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background { FrostedHeaderBackground() }
        .accessibilityIdentifier("feed.header")
    }
}

// MARK: - Sol con carita

/// Botón de sol de la cabecera (F7): 44 pt, halo ámbar difuso de 36 pt y sol de 28 pt con el
/// destello solar (12 s lineal: rayos 0 → 180 → 0°, escala 1 → 1,1, resplandor ámbar 6 → 14 px).
/// Al tocarlo, un destello de un disparo (1 → 1,15 → 1 en 450 ms) antes de abrir Extraer.
struct FeedSunSpiritButton: View {
    let action: () -> Void

    @State private var flashes = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    var body: some View {
        Button(action: tap) {
            ZStack {
                SunHalo()
                AmbientTimeline(frameInterval: MotionSpec.slowFrameInterval) { t in
                    let s = SolarSparkleModifier.state(at: t)
                    FeedSunSpirit(rayRotation: s.rotation, rayScale: s.scale)
                        .shadow(color: s.shadow.color.color, radius: s.shadow.radius)
                }
                .frame(width: 28, height: 28)
                .keyframeAnimator(initialValue: 1.0, trigger: flashes) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1.15, duration: 0.2)
                        CubicKeyframe(1.0, duration: 0.25)
                    }
                }
            }
            .frame(width: Sizes.headerButton, height: Sizes.headerButton)
            // Pista de la acción (FIDELITY §2.2): cámara diminuta abajo a la derecha del sol.
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(Theme.containerLowest.opacity(0.92)))
                    .overlay(Circle().strokeBorder(TailwindColor.amber300.opacity(0.6).color, lineWidth: 0.5))
                    .offset(x: -4, y: -5)
                    .accessibilityHidden(true)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Analizar una foto")
        .accessibilityIdentifier("feed.header.sun")
    }

    private func tap() {
        guard !(systemReduceMotion || forcedReduceMotion) else {
            action()
            return
        }
        flashes += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            action()
        }
    }
}

/// Sol con carita dibujado para ChromaSol (viewBox 32): ocho rayos en forma de pétalo
/// (largos hasta 14 `#F59E0B`, cortos hasta 12,2 `#FBBF24`, base a 9), disco `#F59E0B` r 7 con
/// núcleo dorado degradado r 5,5, ojos ovalados con brillo, mejillas y sonrisa. Los rayos giran
/// y crecen con el destello; la cara queda siempre derecha. Decorativo (sin VoiceOver).
struct FeedSunSpirit: View {
    var rayRotation: Double = 0
    var rayScale: Double = 1

    var body: some View {
        Canvas { context, size in
            let u = size.width / 32
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - r) * u, y: (cy - r) * u, width: 2 * r * u, height: 2 * r * u))
            }

            // Rayos-pétalo alrededor del centro.
            var rays = context
            rays.translateBy(x: 16 * u, y: 16 * u)
            rays.rotate(by: .degrees(rayRotation))
            rays.scaleBy(x: rayScale, y: rayScale)
            for i in 0..<8 {
                let long = i % 2 == 0
                let tip: CGFloat = long ? 14 : 12.2
                let base: CGFloat = 9
                let half: CGFloat = long ? 1.75 : 1.4
                var ray = Path()
                ray.move(to: CGPoint(x: -half * u, y: -base * u))
                ray.addQuadCurve(to: CGPoint(x: 0, y: -tip * u), control: CGPoint(x: -half * 0.55 * u, y: -(base + tip) / 2 * u))
                ray.addQuadCurve(to: CGPoint(x: half * u, y: -base * u), control: CGPoint(x: half * 0.55 * u, y: -(base + tip) / 2 * u))
                ray.closeSubpath()
                var r = rays
                r.rotate(by: .degrees(Double(i) * 45))
                r.fill(ray, with: .color(Color(brand: long ? 0xF59E0B : 0xFBBF24)))
            }

            // Disco y núcleo.
            context.fill(circle(16, 16, 7), with: .color(Color(brand: 0xF59E0B)))
            context.fill(circle(16, 16, 5.5),
                         with: .radialGradient(Gradient(colors: [Color(brand: 0xFEF9C3), Color(brand: 0xFDE047), Color(brand: 0xFBBF24)]),
                                               center: p(15, 14.6), startRadius: 0, endRadius: 6.4 * u))

            // Carita: ojos ovalados con brillo, mejillas y sonrisa.
            let face = Color(brand: 0x713700)
            for x in [CGFloat(13.7), 18.3] {
                context.fill(Path(ellipseIn: CGRect(x: (x - 0.8) * u, y: 14.1 * u, width: 1.6 * u, height: 2.1 * u)), with: .color(face))
                context.fill(circle(x + 0.3, 14.7, 0.32), with: .color(.white.opacity(0.9)))
            }
            for x in [CGFloat(12.4), 19.6] {
                context.fill(circle(x, 17.3, 0.9), with: .color(Color(brand: 0xF87171, opacity: 0.55)))
            }
            var smile = Path()
            smile.move(to: p(14.4, 17.7))
            smile.addQuadCurve(to: p(17.6, 17.7), control: p(16, 19.5))
            context.stroke(smile, with: .color(face), style: StrokeStyle(lineWidth: 0.85 * u, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar local

/// Avatar del Feed (F8–F9): el brote en maceta de la marca sobre un círculo de 32 pt (melocotón
/// que funde a musgo claro, como un retrato soleado),
/// placa `secondary-fixed` de 2 pt, aro `amber-300/60`, halo `0 0 12px` ámbar 35 % e insignia
/// «✦» que late cuando hay combinaciones nuevas en el jardín. Tocar abre el Jardín.
struct FeedGardenAvatarButton: View {
    var newUnlocks: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(RadialGradient(colors: [Theme.secondaryFixed, Tone.moss.badgeFill], center: UnitPoint(x: 0.5, y: 0.35),
                                     startRadius: 2, endRadius: 20))
                .overlay {
                    BrandTabIconFrame(kind: .jardin, size: 23)
                        .offset(y: 1.5)
                }
                .frame(width: Sizes.avatar, height: Sizes.avatar)
                .glowRing(.header, sparkleBadge: newUnlocks > 0)
                .frame(width: Sizes.headerButton, height: Sizes.headerButton)
                .contentShape(Circle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(Self.accessibilityLabel(newUnlocks: newUnlocks))
        .accessibilityIdentifier("feed.header.avatar")
    }

    static func accessibilityLabel(newUnlocks: Int) -> String {
        switch newUnlocks {
        case ...0: "Tu jardín"
        case 1: "Tu jardín, 1 combinación nueva"
        default: "Tu jardín, \(newUnlocks) combinaciones nuevas"
        }
    }
}
