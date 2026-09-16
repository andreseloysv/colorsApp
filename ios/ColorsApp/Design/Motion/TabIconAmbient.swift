// Movimiento de las pestañas INACTIVAS. En el ejemplo del usuario las cuatro criaturas
// llevan su animación puesta siempre (bote 2,2 s, aleteo 2 s, mecido 3,2 s y vaivén 2,6 s
// están en la clase del elemento del ejemplo, no en el estado
// activo): la barra entera respira. La primera implementación solo animaba la activa y la
// barra se veía apagada (medido: 0 px de diferencia entre fotogramas en las tres inactivas).
//
// Aquí las inactivas usan los MISMOS tiempos con amplitud reducida (45 %) y un reloj más
// lento (15 fps), que es lo que cuesta poco y no roba la mirada a la pestaña activa:
//   - sin anillo de ping ni halo verde (siguen siendo solo de la activa),
//   - el parpadeo se conserva entero (es un guiño, no una amplitud),
//   - las alas de la libélula quedan quietas: su ciclo es de 0,18 s y a 15 fps (2,7
//     muestras por ciclo) se vería como parpadeo aleatorio, no como vibración,
//   - cada pestaña arranca con un desfase distinto para que no vayan al unísono.
// Todo pasa por `AmbientTimeline`, así que respeta «Reducir movimiento», el segundo plano,
// el Ahorro de energía y el reposo de 30 s igual que el resto del ambiente.
import SwiftUI

extension MotionSpec {
    /// Pestañas inactivas.
    enum TabIdle {
        /// Fracción de la amplitud de la pestaña activa (0 = quieta, 1 = igual que la activa).
        static let amplitude: Double = 0.45
        /// Reloj propio: la mitad de fotogramas que lo ambiental normal.
        static let framesPerSecond: Double = 15
        static var frameInterval: Double { 1 / framesPerSecond }

        /// Desfase inicial por pestaña (s) para que las cuatro no se muevan al unísono.
        static func phase(_ kind: BrandTabIconKind) -> Double {
            switch kind {
            case .feed: 0
            case .extraer: 0.35
            case .rejilla: 0.7
            case .jardin: 1.05
            }
        }
    }
}

extension TabIconPose {
    /// Mezcla con la pose de reposo: `amount` 0 = reposo, 1 = esta pose. Solo atenúa
    /// desplazamiento, escala y rotación del cuerpo; apaga ping y chispa y deja las alas
    /// quietas (ver cabecera).
    func damped(_ amount: Double) -> TabIconPose {
        let a = min(max(amount, 0), 1)
        func mix(_ value: Double, rest: Double) -> Double { rest + (value - rest) * a }
        var pose = TabIconPose()
        pose.offsetY = mix(offsetY, rest: TabIconPose.rest.offsetY)
        pose.scaleX = mix(scaleX, rest: TabIconPose.rest.scaleX)
        pose.scaleY = mix(scaleY, rest: TabIconPose.rest.scaleY)
        pose.rotation = mix(rotation, rest: TabIconPose.rest.rotation)
        pose.eyeScaleY = eyeScaleY
        return pose
    }
}

extension BrandMotion {
    /// Pose de una pestaña INACTIVA en `time` segundos (nil = reposo, con «Reducir movimiento»).
    static func ambientPose(_ kind: BrandTabIconKind, at time: Double?,
                            amplitude: Double = MotionSpec.TabIdle.amplitude) -> TabIconPose {
        guard let time else { return .rest }
        let t = time + MotionSpec.TabIdle.phase(kind)
        return pose(kind, at: t, active: true, reduceMotion: false).damped(amplitude)
    }
}

/// Icono de pestaña inactivo con su respiración de fondo (lo usa `BrandTabIcon`).
struct AmbientTabIcon: View {
    let kind: BrandTabIconKind
    var size: CGFloat = 28

    var body: some View {
        AmbientTimeline(frameInterval: MotionSpec.TabIdle.frameInterval) { time in
            BrandTabIconFrame(kind: kind, pose: BrandMotion.ambientPose(kind, at: time), size: size)
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}
