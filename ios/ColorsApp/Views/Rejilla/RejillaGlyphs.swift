// Glifos y luces propios de la Rejilla (captura «la_rejilla» del ejemplo del usuario,
// docs/design/FIDELITY.md §5 filas R8–R15): estrella de ocho puntas del rótulo, sol en trazo
// del reloj de sol, disco con aro discontinuo y aro exterior, y puntos de luz de la tarjeta al
// azar. Geometría original dibujada con `Path` (formas geométricas genéricas).
// Todo es MARCO: nada de esto se pinta dentro de un pocillo ni junto a un swatch.
import SwiftUI

// MARK: - Formas

/// Estrella de ocho puntas (brújula solar): radio exterior 1 y radio interior 0,42 del lado.
struct SolarCompassStar: Shape {
    var points: Int = 8
    var innerRatio: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var p = Path()
        let count = max(points, 3) * 2
        for i in 0..<count {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(max(points, 3))
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Sol en trazo del reloj de sol (caja 24): disco r 4, ocho rayos de 2 unidades a 8–10 del centro
/// y medio arco interior r 3 a la izquierda. Se dibuja con `stroke` (trazo 2 en la caja 24).
struct SunDialGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.addEllipse(in: CGRect(x: ox + 8 * s, y: oy + 8 * s, width: 8 * s, height: 8 * s))
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4
            p.move(to: pt(12 + 8 * cos(a), 12 + 8 * sin(a)))
            p.addLine(to: pt(12 + 10 * cos(a), 12 + 10 * sin(a)))
        }
        // Medio arco interior (de arriba a abajo por la izquierda).
        p.move(to: pt(12, 9))
        p.addArc(center: pt(12, 12), radius: 3 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        return p
    }
}

// MARK: - Colores de luz (marco)

/// Colores fijos de las luces de la Rejilla (`code.html`): se usan solo en el marco.
enum RejillaLight {
    /// `secondary-container` #FD933F: disco y halo del reloj de sol, orbe cálido.
    static let solarOrange: UInt32 = 0xFD933F
    /// `secondary-fixed` #FFDCC6: punto con ping y aura de la tarjeta.
    static let peach: UInt32 = 0xFFDCC6
    /// `primary-fixed` #BCEFC7: orbe verde y punto con pulso.
    static let mint: UInt32 = 0xBCEFC7
    /// `rgba(217,119,36,…)`: resplandor de la estrella y del sol del reloj.
    static let ember: UInt32 = 0xD97724
    /// `primary` #144226: halo del botón «Otra» en claro.
    static let moss: UInt32 = 0x144226
    /// Musgo claro #A1D2AC: el mismo halo en oscuro (el musgo oscuro no se ve sobre tierra oscura).
    static let mossNight: UInt32 = 0xA1D2AC
}

// MARK: - Piezas

/// Rótulo con estrella que gira (8 s, resplandor `0 0 4px rgba(217,119,36,0.6)`) y «✦».
struct RejillaEyebrow: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            SolarCompassStar()
                .fill(Theme.secondary)
                .frame(width: 16, height: 16)
                .shadow(color: Color(brand: RejillaLight.ember, opacity: 0.6), radius: 2)
                .spinning(duration: 8)
                .accessibilityHidden(true)
            Text(title)
                .textRole(.overline)
                .foregroundStyle(Theme.secondary)
                .shadow(color: .black.opacity(0.05), radius: 0.5, x: 0, y: 1)
                .lineLimit(1)
            Text("✦")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Reloj de sol de 48 pt (56 pt con el aro exterior): disco `#FD933F` al 20 % con halo
/// `0 0 16px` al 35 % y filo de luz, filo `secondary` al 30 %, aro discontinuo que gira en 10 s,
/// aro exterior con pulso y sol en trazo con resplandor que gira +360° + [0, 180)° al barajar.
struct RejillaSunDial: View {
    /// Giro acumulado del sol (lo anima quien baraja).
    var rotation: Double

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.secondary.opacity(0.2), lineWidth: 1)
                .frame(width: 56, height: 56)
                .pulse()
            Circle()
                .fill(Color(brand: RejillaLight.solarOrange, opacity: 0.2))
                .background(OuterGlow(shape: Circle(), shadows: [ShadowSpec(MotionRGBA(hex: RejillaLight.solarOrange, alpha: 0.35), blur: 16)]))
                .overlay(Circle().strokeBorder(Theme.secondary.opacity(0.3), lineWidth: 1))
                .insetSunGlint(Circle(), opacity: MotionSpec.Glint.strong)
                .frame(width: 48, height: 48)
            Circle()
                .strokeBorder(Theme.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [3.5, 3]))
                .frame(width: 48, height: 48)
                .spinning(duration: MotionSpec.Spin.gridSlow)
            SunDialGlyph()
                .stroke(Theme.secondary, style: StrokeStyle(lineWidth: 2 * 28 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 28, height: 28)
                .shadow(color: Color(brand: RejillaLight.ember, opacity: 0.7), radius: 3)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

/// Punto de luz con halo (`w-2 h-2 rounded-full bg-X shadow-[0_0_Bpx_X]`), con ping o pulso.
struct RejillaGlowDot: View {
    enum Motion { case ping, pulse }

    let color: Color
    var size: CGFloat
    var glowBlur: CGFloat
    var opacity: Double
    var motion: Motion

    var body: some View {
        let dot = Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: glowBlur / 2)
        Group {
            switch motion {
            case .ping: dot.pingDot()
            case .pulse: dot.pulse()
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
