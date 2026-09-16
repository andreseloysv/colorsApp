// Recetas de movimiento de docs/design/FIDELITY.md §1 (boceto de referencia, no se compila en la app).
// Comprobado: xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 6 \
//   -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) ambient-recipes.swift  → exit 0
import SwiftUI
import UIKit
import Observation

// MARK: Política de ambiente

extension EnvironmentValues {
    /// La inyecta RootTabContainer: true solo en la pestaña visible (las ocultas siguen vivas con opacidad 0).
    @Entry var isTabActive: Bool = true
    /// DEBUG: reloj congelado para capturas reproducibles (`-uiAmbientTime 1.25`).
    @Entry var ambientFrozenTime: TimeInterval? = nil
}

@Observable @MainActor
final class AmbientActivity {
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var lastInteraction = Date()
    var isResting: Bool { Date().timeIntervalSince(lastInteraction) > 30 }
    func touch() { lastInteraction = Date() }
}

/// Reloj ambiental: ≤ 30 fps, pausado fuera de pantalla, en segundo plano, con Reducir movimiento,
/// en Ahorro de energía, en pestañas ocultas y en reposo. `nil` = pose de reposo.
struct AmbientTimeline<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.ambientFrozenTime) private var frozen
    @Environment(AmbientActivity.self) private var activity
    @State private var onScreen = false
    @ViewBuilder let content: (TimeInterval?) -> Content

    var body: some View {
        let paused = reduceMotion || !isTabActive || scenePhase != .active || !onScreen
            || activity.lowPower || activity.isResting
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused || frozen != nil)) { ctx in
            content(frozen ?? (paused ? nil : ctx.date.timeIntervalSinceReferenceDate))
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}

// MARK: Curvas CSS exactas

enum CSSCurve {
    static let ease = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1), endControlPoint: UnitPoint(x: 0.25, y: 1))
    static let easeOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))
    static let easeInOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.42, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))
    static let tailwindPing = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))
    static let tailwindPulse = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.6, y: 1))
}

// MARK: M3 bote (M3, 2,2 s) con KeyframeTimeline muestreado por el reloj

struct BouncePose { var y: CGFloat = 0; var sx: CGFloat = 1; var sy: CGFloat = 1 }

@MainActor
enum Keyframes {
    static let bounce = KeyframeTimeline(initialValue: BouncePose()) {
        KeyframeTrack(\.y) {
            LinearKeyframe(-3, duration: 0.66, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(-5, duration: 0.44, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(-1, duration: 0.44, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(0, duration: 0.66, timingCurve: CSSCurve.easeInOut)
        }
        KeyframeTrack(\.sx) {
            LinearKeyframe(0.95, duration: 0.66, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(1.04, duration: 0.44, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(0.98, duration: 0.44, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(1, duration: 0.66, timingCurve: CSSCurve.easeInOut)
        }
        KeyframeTrack(\.sy) {
            LinearKeyframe(1.08, duration: 0.66, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(0.96, duration: 0.44, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(1.02, duration: 0.44, timingCurve: CSSCurve.easeInOut)
            LinearKeyframe(1, duration: 0.66, timingCurve: CSSCurve.easeInOut)
        }
    }

    /// Tailwind `animate-ping`: 1 s, 0–75 % escala 1→2 y opacidad 1→0, 75–100 % quieto.
    static func ping(_ t: TimeInterval) -> (scale: CGFloat, opacity: Double) {
        let p = t.truncatingRemainder(dividingBy: 1.0)
        guard p < 0.75 else { return (2, 0) }
        let k = CSSCurve.tailwindPing.value(at: p / 0.75)
        return (1 + k, 1 - k)
    }

    /// Tailwind `animate-pulse`: 2 s, opacidad 1→0,5→1.
    static func pulse(_ t: TimeInterval) -> Double {
        let p = t.truncatingRemainder(dividingBy: 2.0) / 2.0
        let half = p < 0.5 ? p / 0.5 : (1 - p) / 0.5
        return 1 - 0.5 * CSSCurve.tailwindPulse.value(at: half)
    }
}

// MARK: M1 motas en Canvas con exclusión de pocillos

struct Mote { let x, bottom, size: CGFloat; let fill: Color; let glow: Color; let blur: CGFloat; let duration, delay: Double }

@Observable @MainActor
final class AmbientExclusions { var rects: [CGRect] = [] }

struct AmbientMotes: View {
    let motes: [Mote]
    @Environment(AmbientExclusions.self) private var exclusions

    var body: some View {
        AmbientTimeline { time in
            Canvas { ctx, size in
                guard let time else { return }
                for m in motes {
                    let local = time - m.delay
                    guard local >= 0 else { continue }
                    let p = local.truncatingRemainder(dividingBy: m.duration) / m.duration
                    let move = CSSCurve.easeOut.value(at: p)
                    let opacity: Double = p < 0.2 ? 0.8 * CSSCurve.easeOut.value(at: p / 0.2)
                        : p < 0.8 ? 0.8 - 0.2 * CSSCurve.easeOut.value(at: (p - 0.2) / 0.6)
                        : 0.6 * (1 - CSSCurve.easeOut.value(at: (p - 0.8) / 0.2))
                    let c = CGPoint(x: size.width * m.x + 15 * move, y: size.height * (1 - m.bottom) - 120 * move)
                    let r = CGRect(x: c.x - m.size / 2, y: c.y - m.size / 2, width: m.size, height: m.size)
                    if exclusions.rects.contains(where: { $0.insetBy(dx: -8, dy: -8).intersects(r) }) { continue }
                    ctx.drawLayer { layer in
                        layer.opacity = opacity
                        layer.addFilter(.shadow(color: m.glow, radius: m.size))
                        layer.addFilter(.blur(radius: m.blur))
                        layer.fill(Path(ellipseIn: r), with: .color(m.fill))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: L1 tarjeta con halo + M2 respiración

struct GlowCard: ViewModifier {
    var breathing: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content.background {
            AmbientTimeline { time in
                let b = breathing ? breath(time) : 0
                shape.fill(Color(red: 241 / 255, green: 238 / 255, blue: 230 / 255))
                    .shadow(color: mix(amber: 0.22 + 0.08 * b, teal: 0.35 * b), radius: 9 + 3 * b)
                    .shadow(color: Color(red: 45 / 255, green: 90 / 255, blue: 60 / 255).opacity(0.12 + 0.03 * b), radius: 14 + 4 * b)
                    .overlay(shape.strokeBorder(Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255).opacity(0.25 + 0.15 * b), lineWidth: 1))
            }
        }
    }
    private func breath(_ t: TimeInterval?) -> Double {
        guard let t else { return 0 }
        let p = t.truncatingRemainder(dividingBy: 4.0) / 4.0
        return CSSCurve.easeInOut.value(at: p < 0.5 ? p * 2 : (1 - p) * 2)
    }
    private func mix(amber: Double, teal: Double) -> Color {
        teal > amber ? Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255).opacity(teal)
                     : Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255).opacity(amber)
    }
}

// MARK: M13 barrido de luz (2,5 s) bajo el texto del botón

struct Shimmer: View {
    var body: some View {
        GeometryReader { geo in
            AmbientTimeline { time in
                let p = (time ?? 0).truncatingRemainder(dividingBy: 2.5) / 2.5
                LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width)
                    .offset(x: time == nil ? -geo.size.width * 2 : geo.size.width * (2 * CSSCurve.ease.value(at: p) - 1))
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }
}

// MARK: Microinteracciones con símbolos (iOS 17)

struct SymbolDemo: View {
    @State var yes = false
    @State var copied = false
    var body: some View {
        HStack {
            Image(systemName: yes ? "heart.fill" : "heart").symbolEffect(.bounce, value: yes)
            Image(systemName: copied ? "checkmark" : "doc.on.doc").contentTransition(.symbolEffect(.replace))
            Image(systemName: "sparkles").symbolEffect(.pulse, options: .repeating, isActive: !yes)
        }
    }
}

// MARK: Personaje en Canvas con pose muestreada

struct SeedCreature: View {
    var body: some View {
        AmbientTimeline { time in
            let pose = time.map { Keyframes.bounce.value(time: $0.truncatingRemainder(dividingBy: Keyframes.bounce.duration)) } ?? BouncePose()
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / 24, y: size.height / 24)
                ctx.translateBy(x: 12, y: 12 + pose.y)
                ctx.scaleBy(x: pose.sx, y: pose.sy)
                ctx.translateBy(x: -12, y: -12)
                ctx.fill(Path(ellipseIn: CGRect(x: 4.5, y: 4.5, width: 15, height: 15)), with: .color(Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)))
            }
            .frame(width: 24, height: 24)
        }
    }
}
