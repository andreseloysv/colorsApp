// Tiempos de la marca: evaluador de @keyframes CSS y poses de los iconos de pestaña y del
// sol del logotipo, con los valores EXACTOS de exampleDesign/…/solar_feed…/code.html
// (bote 2,2 s, parpadeo 3,4 s, aleteo 2 s con alas a 0,18 s, balanceo 3,2 s y 2,6 s,
// destello solar 12 s, animate-pulse 2 s y animate-ping 1 s de Tailwind).
// Solo matemática (Foundation): sin UIKit, para compilar también en el script de macOS
// que renderiza el icono de la app. Con Reduce Motion todas las poses son la de reposo.
import Foundation

/// Curva `cubic-bezier(x1, y1, x2, y2)` de CSS (x en tiempo, y en progreso).
struct CSSTimingCurve: Sendable, Equatable {
    let x1: Double, y1: Double, x2: Double, y2: Double

    static let linear = CSSTimingCurve(x1: 0, y1: 0, x2: 1, y2: 1)
    /// `ease-in-out` de CSS.
    static let easeInOut = CSSTimingCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    /// `ease-out` de CSS.
    static let easeOut = CSSTimingCurve(x1: 0, y1: 0, x2: 0.58, y2: 1)
    /// `animate-pulse` de Tailwind.
    static let tailwindPulse = CSSTimingCurve(x1: 0.4, y1: 0, x2: 0.6, y2: 1)
    /// `animate-ping` de Tailwind.
    static let tailwindPing = CSSTimingCurve(x1: 0, y1: 0, x2: 0.2, y2: 1)

    /// Progreso para un tiempo normalizado `x` en 0…1.
    func value(at x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if self == .linear { return x }
        // Resolver t con Newton y, si no converge, bisección.
        func bx(_ t: Double) -> Double { bezier(t, x1, x2) }
        func by(_ t: Double) -> Double { bezier(t, y1, y2) }
        var t = x
        for _ in 0..<8 {
            let err = bx(t) - x
            if abs(err) < 1e-7 { return by(t) }
            let d = derivative(t, x1, x2)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<40 {
            let v = bx(t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return by(t)
    }

    private func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    private func derivative(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }
}

/// Pista de una propiedad: pares (desplazamiento 0…1, valor) y la curva que CSS aplica
/// a cada tramo entre fotogramas clave (`animation-timing-function`).
struct CSSKeyframeTrack: Sendable, Equatable {
    let stops: [(offset: Double, value: Double)]
    let curve: CSSTimingCurve

    init(_ stops: [(Double, Double)], curve: CSSTimingCurve) {
        self.stops = stops.map { (offset: $0.0, value: $0.1) }.sorted { $0.offset < $1.offset }
        self.curve = curve
    }

    static func == (a: CSSKeyframeTrack, b: CSSKeyframeTrack) -> Bool {
        a.curve == b.curve && a.stops.count == b.stops.count
            && zip(a.stops, b.stops).allSatisfy { $0.offset == $1.offset && $0.value == $1.value }
    }

    /// Valor en el progreso `p` (0…1) del ciclo.
    func value(at p: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if p <= first.offset { return first.value }
        if p >= last.offset { return last.value }
        for i in 1..<stops.count where p <= stops[i].offset {
            let a = stops[i - 1], b = stops[i]
            let span = b.offset - a.offset
            guard span > 0 else { return b.value }
            let local = curve.value(at: (p - a.offset) / span)
            return a.value + (b.value - a.value) * local
        }
        return last.value
    }
}

/// Una animación CSS infinita: duración, retraso y pistas.
struct CSSLoop: Sendable {
    let duration: Double
    var delay: Double = 0

    /// Progreso 0…1 del ciclo en el instante `t` (s). Antes del retraso, 0 (fotograma inicial).
    func progress(at t: Double) -> Double {
        let local = t - delay
        guard duration > 0, local > 0 else { return 0 }
        return local.truncatingRemainder(dividingBy: duration) / duration
    }
}

// MARK: - Animaciones del ejemplo (valores de code.html)

enum BrandKeyframes {
    // Bote de la semilla solar (keyframe de bote del Feed: `2.2s infinite ease-in-out`).
    static let bounce = CSSLoop(duration: 2.2)
    static let bounceY = CSSKeyframeTrack([(0, 0), (0.30, -3), (0.50, -5), (0.70, -1), (1, 0)], curve: .easeInOut)
    static let bounceScaleX = CSSKeyframeTrack([(0, 1), (0.30, 0.95), (0.50, 1.04), (0.70, 0.98), (1, 1)], curve: .easeInOut)
    static let bounceScaleY = CSSKeyframeTrack([(0, 1), (0.30, 1.08), (0.50, 0.96), (0.70, 1.02), (1, 1)], curve: .easeInOut)

    // Parpadeo (`3.4s infinite ease-in-out`: 0, 92, 100 % scaleY 1; 96 % 0,1).
    static let blink = CSSLoop(duration: 3.4)
    static let blinkScaleY = CSSKeyframeTrack([(0, 1), (0.92, 1), (0.96, 0.1), (1, 1)], curve: .easeInOut)

    // Libélula (`dragonfly-flutter 2s infinite ease-in-out`).
    static let flutter = CSSLoop(duration: 2)
    static let flutterRotation = CSSKeyframeTrack([(0, 0), (0.25, -5), (0.75, 6), (1, 0)], curve: .easeInOut)
    static let flutterScale = CSSKeyframeTrack([(0, 1), (0.25, 1.05), (0.75, 0.98), (1, 1)], curve: .easeInOut)

    // Alas (`wing-vibrate 0.18s infinite linear`).
    static let wings = CSSLoop(duration: 0.18)
    static let wingOpacity = CSSKeyframeTrack([(0, 0.7), (0.5, 0.3), (1, 0.7)], curve: .linear)
    static let wingScaleY = CSSKeyframeTrack([(0, 1), (0.5, 0.55), (1, 1)], curve: .linear)

    // Gota que se mece (keyframe de balanceo de la Rejilla: `3.2s infinite ease-in-out`, origen abajo al centro).
    static let bob = CSSLoop(duration: 3.2)
    static let bobRotation = CSSKeyframeTrack([(0, 0), (0.25, -8), (0.60, 7), (0.80, -3), (1, 0)], curve: .easeInOut)
    static let bobY = CSSKeyframeTrack([(0, 0), (0.25, -1.5), (0.60, 0.5), (0.80, -0.5), (1, 0)], curve: .easeInOut)

    // Brote (`sprout-sway 2.6s infinite ease-in-out`, origen abajo al centro).
    static let sway = CSSLoop(duration: 2.6)
    static let swayRotation = CSSKeyframeTrack([(0, 0), (0.35, 6), (0.75, -5), (1, 0)], curve: .easeInOut)
    static let swayY = CSSKeyframeTrack([(0, 0), (0.35, -1), (0.75, 0.5), (1, 0)], curve: .easeInOut)

    // Destello solar (`solar-sparkle 12s infinite linear`): 0/100 % rotate 0, scale 1,
    // drop-shadow 6 px ámbar 0,6; 50 % rotate 180°, scale 1,1, drop-shadow 14 px ámbar 0,9.
    static let sparkle = CSSLoop(duration: 12)
    static let sparkleRotation = CSSKeyframeTrack([(0, 0), (0.5, 180), (1, 0)], curve: .linear)
    static let sparkleScale = CSSKeyframeTrack([(0, 1), (0.5, 1.1), (1, 1)], curve: .linear)
    static let sparkleGlowBlur = CSSKeyframeTrack([(0, 6), (0.5, 14), (1, 6)], curve: .linear)
    static let sparkleGlowOpacity = CSSKeyframeTrack([(0, 0.6), (0.5, 0.9), (1, 0.6)], curve: .linear)

    // `animate-pulse` (2 s): opacidad 1 → 0,5 → 1.
    static let pulse = CSSLoop(duration: 2)
    static let pulseOpacity = CSSKeyframeTrack([(0, 1), (0.5, 0.5), (1, 1)], curve: .tailwindPulse)

    // `animate-ping` (1 s): 75 %, 100 % scale 2 y opacidad 0.
    static let ping = CSSLoop(duration: 1)
    static let pingScale = CSSKeyframeTrack([(0, 1), (0.75, 2), (1, 2)], curve: .tailwindPing)
    static let pingOpacity = CSSKeyframeTrack([(0, 1), (0.75, 0), (1, 0)], curve: .tailwindPing)
}

// MARK: - Poses

/// Los cuatro iconos de pestaña (personajes originales de la marca).
enum BrandTabIconKind: String, CaseIterable, Identifiable, Sendable {
    /// Semilla solar con carita: bota (2,2 s) y parpadea (3,4 s).
    case feed
    /// Libélula de alas translúcidas: aletea (2 s) con alas que vibran (0,18 s).
    case extraer
    /// Gotita de rocío con brote y reflejo de rejilla: se mece (3,2 s).
    case rejilla
    /// Brote en maceta: se balancea (2,6 s).
    case jardin

    var id: String { rawValue }

    /// Título de la pestaña (§6.2).
    var title: String {
        switch self {
        case .feed: "Feed"
        case .extraer: "Extraer"
        case .rejilla: "Rejilla"
        case .jardin: "Jardín"
        }
    }

    /// Rótulo de sección de la cabecera («FEED», «EXTRAER», «REJILLA», «JARDÍN»).
    var sectionLabel: String { title.uppercased(with: Locale(identifier: "es_ES")) }

    /// Identificador de accesibilidad de la pestaña en `SolarTabs.standard` («tab.feed»…).
    var tabIdentifier: String { "tab.\(rawValue)" }

    /// Tipo a partir del identificador de `SolarTabItem` («tab.feed» → `.feed`).
    init?(tabIdentifier: String) {
        guard tabIdentifier.hasPrefix("tab.") else { return nil }
        self.init(rawValue: String(tabIdentifier.dropFirst(4)))
    }

    /// Descripción del personaje para VoiceOver en la galería (la pestaña usa solo su título).
    var characterDescription: String {
        switch self {
        case .feed: "Semilla solar con carita"
        case .extraer: "Libélula de alas translúcidas"
        case .rejilla: "Gotita de rocío con un brote"
        case .jardin: "Brote en maceta"
        }
    }
}

/// Pose de un icono de pestaña en un instante. Unidades de desplazamiento: las del
/// viewBox 24 × 24 del ejemplo (se escalan al tamaño real al dibujar).
struct TabIconPose: Sendable, Equatable {
    /// Traslación vertical del cuerpo (unidades del viewBox).
    var offsetY: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    /// Rotación del cuerpo en grados (horario positivo, como CSS).
    var rotation: Double = 0
    /// Escala vertical de los ojos (parpadeo).
    var eyeScaleY: Double = 1
    /// Opacidad y escala vertical de las alas (libélula).
    var wingOpacity: Double = 0.7
    var wingScaleY: Double = 1
    /// Anillo de la mota que late (`animate-ping`): escala y opacidad; 0 = sin anillo.
    var pingScale: Double = 1
    var pingOpacity: Double = 0
    /// Opacidad de la chispa que late (`animate-pulse`).
    var sparkOpacity: Double = 1

    /// Pose quieta (primer fotograma de cada animación, sin anillo de ping).
    static let rest = TabIconPose()
}

/// Pose del sol del logotipo (`solar-sparkle`).
struct SunSparklePose: Sendable, Equatable {
    var rotation: Double = 0
    var scale: Double = 1
    /// Desenfoque CSS del drop-shadow en px (SwiftUI usa radio ≈ px / 2).
    var glowBlur: Double = 6
    var glowOpacity: Double = 0.6

    static let rest = SunSparklePose()
}

/// Halo de la pestaña activa: opacidad (`animate-pulse`).
struct TabHaloPose: Sendable, Equatable {
    var opacity: Double = 1
    static let rest = TabHaloPose()
}

enum BrandMotion {
    /// Fotogramas por segundo máximos de todo lo ambiental de la marca.
    static let maxFramesPerSecond: Double = 30

    /// ¿Debe correr el reloj? Solo sin Reduce Motion, con la escena activa y si se pide animar.
    static func isRunning(animated: Bool, reduceMotion: Bool, sceneActive: Bool) -> Bool {
        animated && !reduceMotion && sceneActive
    }

    /// Pose de un icono en el instante `t` (s). Inactivo o con Reduce Motion: reposo.
    static func pose(_ kind: BrandTabIconKind, at t: Double, active: Bool, reduceMotion: Bool) -> TabIconPose {
        guard active, !reduceMotion else { return .rest }
        var pose = TabIconPose()
        let ping = BrandKeyframes.ping.progress(at: t)
        pose.pingScale = BrandKeyframes.pingScale.value(at: ping)
        pose.pingOpacity = BrandKeyframes.pingOpacity.value(at: ping)
        pose.sparkOpacity = BrandKeyframes.pulseOpacity.value(at: BrandKeyframes.pulse.progress(at: t))
        switch kind {
        case .feed:
            let p = BrandKeyframes.bounce.progress(at: t)
            pose.offsetY = BrandKeyframes.bounceY.value(at: p)
            pose.scaleX = BrandKeyframes.bounceScaleX.value(at: p)
            pose.scaleY = BrandKeyframes.bounceScaleY.value(at: p)
            pose.eyeScaleY = BrandKeyframes.blinkScaleY.value(at: BrandKeyframes.blink.progress(at: t))
        case .extraer:
            let p = BrandKeyframes.flutter.progress(at: t)
            pose.rotation = BrandKeyframes.flutterRotation.value(at: p)
            let s = BrandKeyframes.flutterScale.value(at: p)
            pose.scaleX = s
            pose.scaleY = s
            let w = BrandKeyframes.wings.progress(at: t)
            pose.wingOpacity = BrandKeyframes.wingOpacity.value(at: w)
            pose.wingScaleY = BrandKeyframes.wingScaleY.value(at: w)
        case .rejilla:
            let p = BrandKeyframes.bob.progress(at: t)
            pose.rotation = BrandKeyframes.bobRotation.value(at: p)
            pose.offsetY = BrandKeyframes.bobY.value(at: p)
        case .jardin:
            let p = BrandKeyframes.sway.progress(at: t)
            pose.rotation = BrandKeyframes.swayRotation.value(at: p)
            pose.offsetY = BrandKeyframes.swayY.value(at: p)
        }
        return pose
    }

    /// Pose del sol del logotipo en `t`. Con Reduce Motion o sin animar: reposo.
    static func sparkle(at t: Double, animated: Bool, reduceMotion: Bool) -> SunSparklePose {
        guard animated, !reduceMotion else { return .rest }
        let p = BrandKeyframes.sparkle.progress(at: t)
        return SunSparklePose(rotation: BrandKeyframes.sparkleRotation.value(at: p),
                              scale: BrandKeyframes.sparkleScale.value(at: p),
                              glowBlur: BrandKeyframes.sparkleGlowBlur.value(at: p),
                              glowOpacity: BrandKeyframes.sparkleGlowOpacity.value(at: p))
    }

    /// Halo de la pestaña activa en `t` (late con `animate-pulse`). Con Reduce Motion: fijo.
    static func halo(at t: Double, reduceMotion: Bool) -> TabHaloPose {
        guard !reduceMotion else { return .rest }
        return TabHaloPose(opacity: BrandKeyframes.pulseOpacity.value(at: BrandKeyframes.pulse.progress(at: t)))
    }

    /// Punto ámbar del wordmark (`animate-ping` en un anillo detrás del punto fijo).
    static func wordmarkPing(at t: Double, reduceMotion: Bool) -> (scale: Double, opacity: Double) {
        guard !reduceMotion else { return (1, 0) }
        let p = BrandKeyframes.ping.progress(at: t)
        return (BrandKeyframes.pingScale.value(at: p), BrandKeyframes.pingOpacity.value(at: p))
    }
}
