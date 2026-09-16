// Matemática de movimiento con la semántica de CSS: curvas `cubic-bezier` (las de
// `animation-timing-function`), pistas de fotogramas clave por porcentaje y reloj de
// animación con duración, retraso e iteraciones infinitas. Funciones puras y `Sendable`:
// los efectos (AmbientEffects, LightMotesOverlay) solo muestrean estas pistas con el
// tiempo del `TimelineView`, y los tests comprueban los valores exactos del ejemplo
// (exampleDesign/…/code.html) sin renderizar.
import CoreGraphics
import Foundation

/// Curva de tiempo `cubic-bezier(x1, y1, x2, y2)` de CSS, resuelta como en los navegadores
/// (Newton-Raphson con respaldo por bisección sobre x(t), luego y(t)).
struct CubicBezierCurve: Sendable, Hashable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// `linear`.
    static let linear = CubicBezierCurve(0, 0, 1, 1)
    /// `ease` (valor por defecto de CSS cuando la animación no nombra curva).
    static let ease = CubicBezierCurve(0.25, 0.1, 0.25, 1)
    /// `ease-in`.
    static let easeIn = CubicBezierCurve(0.42, 0, 1, 1)
    /// `ease-out` (motas de luz).
    static let easeOut = CubicBezierCurve(0, 0, 0.58, 1)
    /// `ease-in-out`.
    static let easeInOut = CubicBezierCurve(0.42, 0, 0.58, 1)
    /// Tailwind `animate-ping`: `cubic-bezier(0, 0, 0.2, 1)`.
    static let tailwindPing = CubicBezierCurve(0, 0, 0.2, 1)
    /// Tailwind `animate-pulse`: `cubic-bezier(0.4, 0, 0.6, 1)`.
    static let tailwindPulse = CubicBezierCurve(0.4, 0, 0.6, 1)
    /// Tailwind `transition` por defecto: `cubic-bezier(0.4, 0, 0.2, 1)`.
    static let tailwindTransition = CubicBezierCurve(0.4, 0, 0.2, 1)

    private func sampleX(_ t: Double) -> Double {
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        return ((ax * t + bx) * t + cx) * t
    }

    private func sampleY(_ t: Double) -> Double {
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        return ((ay * t + by) * t + cy) * t
    }

    private func sampleDerivativeX(_ t: Double) -> Double {
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        return (3 * ax * t + 2 * bx) * t + cx
    }

    /// Progreso de salida (0…1, o fuera si la curva rebota) para un progreso de entrada `x` (0…1).
    func value(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if self == .linear { return x }
        let epsilon = 1e-7
        var t = x
        for _ in 0..<8 {
            let dx = sampleX(t) - x
            if abs(dx) < epsilon { return sampleY(t) }
            let d = sampleDerivativeX(t)
            if abs(d) < 1e-6 { break }
            t -= dx / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while lo < hi {
            let v = sampleX(t)
            if abs(v - x) < epsilon { break }
            if x > v { lo = t } else { hi = t }
            t = (hi - lo) / 2 + lo
            if hi - lo < epsilon { break }
        }
        return sampleY(t)
    }
}

/// Valor que se puede interpolar entre dos fotogramas clave.
protocol MotionInterpolable: Sendable {
    static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self
}

extension Double: MotionInterpolable {
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

extension CGPoint: MotionInterpolable {
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: Double.lerp(a.x, b.x, t), y: Double.lerp(a.y, b.y, t))
    }
}

/// Pista de fotogramas clave de CSS para UNA propiedad: paradas por porcentaje (0…1)
/// y la curva que se aplica a cada tramo entre dos paradas que declaran esa propiedad.
/// Las paradas implícitas de CSS (0 % y 100 % con el valor base del elemento) se
/// escriben explícitas.
struct CSSKeyframes<Value: MotionInterpolable>: Sendable {
    struct Stop: Sendable {
        let offset: Double
        let value: Value
    }

    let stops: [Stop]
    let curve: CubicBezierCurve

    init(_ stops: [(Double, Value)], curve: CubicBezierCurve) {
        precondition(stops.count >= 2, "una pista necesita al menos dos paradas")
        self.stops = stops.map { Stop(offset: $0.0, value: $0.1) }.sorted { $0.offset < $1.offset }
        self.curve = curve
    }

    /// Valor a un progreso del ciclo (0…1).
    func value(at progress: Double) -> Value {
        let p = min(max(progress, 0), 1)
        if p <= stops[0].offset { return stops[0].value }
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            if p <= b.offset {
                let span = b.offset - a.offset
                let local = span > 0 ? (p - a.offset) / span : 1
                let eased = curve.value(at: local)
                // Extremos exactos (sin error de redondeo en la interpolación premultiplicada).
                if eased == 0 { return a.value }
                if eased == 1 { return b.value }
                return Value.lerp(a.value, b.value, eased)
            }
        }
        return stops[stops.count - 1].value
    }
}

/// Reloj de una animación CSS `name duration curve delay infinite`.
struct AnimationClock: Sendable, Hashable {
    /// `animation-duration` en segundos.
    let duration: Double
    /// `animation-delay` en segundos.
    var delay: Double = 0

    /// Progreso del ciclo actual (0…1) a `time` segundos desde que empezó la vista, o nil
    /// mientras dura el retraso (antes del primer ciclo).
    func progress(at time: Double) -> Double? {
        guard duration > 0 else { return 0 }
        let local = time - delay
        guard local >= 0 else { return nil }
        let cycles = local / duration
        return cycles - cycles.rounded(.down)
    }
}
