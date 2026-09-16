// Reloj de las animaciones de marca: TimelineView a 30 fps como máximo que solo corre si
// se pide animar, NO hay Reduce Motion, la escena está activa (en segundo plano se para) y
// el ambiente no está en reposo (Ahorro de energía o 30 s sin tocar la pantalla).
// Con Reduce Motion o en pausa pinta un único fotograma de reposo: 0 % de CPU en reposo.
// `brandReduceMotionOverride` y `brandFrozenTime` permiten a tests y galería forzar el
// estado sin tocar los ajustes del sistema.
import SwiftUI

private struct BrandReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct BrandFrozenTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    /// Fuerza Reduce Motion (true/false) por encima del ajuste del sistema; nil = sistema.
    var brandReduceMotionOverride: Bool? {
        get { self[BrandReduceMotionOverrideKey.self] }
        set { self[BrandReduceMotionOverrideKey.self] = newValue }
    }

    /// Congela las animaciones de marca en ese instante (s); nil = reloj real.
    var brandFrozenTime: TimeInterval? {
        get { self[BrandFrozenTimeKey.self] }
        set { self[BrandFrozenTimeKey.self] = newValue }
    }
}

/// Contenedor que entrega el instante (s) y si hay que reducir el movimiento.
struct BrandMotionClock<Content: View>: View {
    /// Si false, pinta siempre el reposo (sin TimelineView).
    var animated: Bool
    @ViewBuilder var content: (_ time: TimeInterval, _ reduceMotion: Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.brandReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.brandFrozenTime) private var frozenTime
    @Environment(\.scenePhase) private var scenePhase
    // Ahorro de energía y reposo de 30 s sin toques (Design/Motion/AmbientActivity.swift):
    // la marca se para con el resto del ambiente.
    @Environment(\.ambientActivity) private var activity

    var body: some View {
        let reduce = reduceMotionOverride ?? systemReduceMotion
        if let frozenTime {
            content(frozenTime, reduce)
        } else if BrandMotion.isRunning(animated: animated, reduceMotion: reduce, sceneActive: scenePhase == .active),
                  activity.allowsAmbientMotion {
            TimelineView(.animation(minimumInterval: 1 / BrandMotion.maxFramesPerSecond)) { timeline in
                content(timeline.date.timeIntervalSinceReferenceDate, reduce)
            }
        } else {
            content(0, reduce)
        }
    }
}
