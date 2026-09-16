// Respuesta al pulsar (el `hover:` / `active:` del ejemplo en táctil): escala
// (`active:scale-95`, `active:scale-[0.98]`, `group-active:scale-90`), elevación
// (`hover:-translate-y-1` = 4 pt) y la transición de Tailwind (150 ms
// `cubic-bezier(0.4, 0, 0.2, 1)`; 300 ms en gotas y tarjetas). En el navegador táctil
// `hover` y `active` se aplican a la vez al pulsar: escala de `active` + desplazamiento
// de `hover`. Con «Reducir movimiento»: sin escala ni desplazamiento, fundido a 0,8 en 150 ms.
// La etiqueta recibe `\.solarButtonPressed` para que sus halos (`glowCard`, `warmShadow`)
// suban al pulsar.
import SwiftUI

private struct SolarButtonPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// true mientras el botón que contiene la vista está pulsado (lo pone `PressScaleButtonStyle`).
    var solarButtonPressed: Bool {
        get { self[SolarButtonPressedKey.self] }
        set { self[SolarButtonPressedKey.self] = newValue }
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    /// Escala pulsada (`active:scale-95` por defecto).
    var scale: CGFloat = MotionSpec.Press.scale
    /// Elevación pulsada en pt (0 = sin desplazamiento).
    var lift: CGFloat = 0
    /// Duración de la transición.
    var duration: Double = MotionSpec.Press.duration

    func makeBody(configuration: Configuration) -> some View {
        PressScaleBody(configuration: configuration, style: self)
    }

    /// Escala y desplazamiento efectivos (los tests los comprueban).
    static func effect(pressed: Bool, reduceMotion: Bool, style: PressScaleButtonStyle) -> (scale: CGFloat, offsetY: CGFloat, opacity: Double) {
        guard pressed else { return (1, 0, 1) }
        return reduceMotion ? (1, 0, 0.8) : (style.scale, -style.lift, 1)
    }
}

private struct PressScaleBody: View {
    let configuration: ButtonStyleConfiguration
    let style: PressScaleButtonStyle
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion

    var body: some View {
        let reduce = systemReduceMotion || forcedReduceMotion
        let e = PressScaleButtonStyle.effect(pressed: configuration.isPressed, reduceMotion: reduce, style: style)
        configuration.label
            .environment(\.solarButtonPressed, configuration.isPressed)
            .scaleEffect(e.scale)
            .offset(y: e.offsetY)
            .opacity(e.opacity)
            .animation(reduce ? .easeOut(duration: MotionSpec.reducedFadeDuration)
                              : .timingCurve(0.4, 0, 0.2, 1, duration: style.duration),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    /// `active:scale-95` (chips, píldoras, iconos de cabecera).
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
    /// `active:scale-[0.98]` (botón a todo el ancho).
    static var pressScaleWide: PressScaleButtonStyle { PressScaleButtonStyle(scale: MotionSpec.Press.wideScale) }
    /// Gota o tarjeta: `scale-90`/`95` + sube 4 pt, 300 ms.
    static func pressLift(scale: CGFloat = MotionSpec.Press.scale, lift: CGFloat = MotionSpec.Press.lift) -> PressScaleButtonStyle {
        PressScaleButtonStyle(scale: scale, lift: lift, duration: MotionSpec.Press.slowDuration)
    }
}
