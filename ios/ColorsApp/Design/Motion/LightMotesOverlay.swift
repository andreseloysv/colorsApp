// Motas de luz que flotan sobre la pantalla (la capa de partículas del Feed del ejemplo):
// cinco puntos con posición (`left`/`bottom` en %), tamaño, color con alfa, `blur`,
// halo de color, duración y retraso exactos (MotionSpec.motes) y la animación de
// flotación: sube 120 pt y deriva 15 pt a la derecha con ease-out, opacidad
// 0 → 0,8 (20 %) → 0,6 (80 %) → 0.
// - `TimelineView` a 20 fps (MotionSpec.moteFrameInterval: ≤ 0,9 pt de avance por fotograma);
//   en pausa (0 fotogramas) en segundo plano, fuera de pantalla, con `.ambientMotion(false)`,
//   en Ahorro de energía, tras 30 s sin tocar la pantalla, y sin dibujar nada con
//   «Reducir movimiento».
// - Durante el retraso inicial la mota está oculta (en CSS, sin `animation-fill-mode`, se vería
//   quieta en su sitio hasta arrancar; aquí se adopta `backwards`, que es lo que se percibe).
// - Zona neutra: `lightMotes()` recorta las motas sobre todo lo marcado con `.neutralZone()`
//   (pocillos, cuentas de color): nunca pasan por encima de un swatch.
import SwiftUI

/// Estado de una mota a un tiempo dado (función pura para tests y capturas).
struct MoteFrame: Sendable, Hashable {
    let center: CGPoint
    let opacity: Double
}

extension MotionSpec.Mote {
    /// Posición y opacidad a `time` segundos del inicio dentro de una capa de `canvas`.
    func frame(at time: Double, in canvas: CGSize) -> MoteFrame {
        let rest = restCenter(in: canvas)
        guard let p = clock.progress(at: time) else { return MoteFrame(center: rest, opacity: 0) }
        let d = MotionSpec.moteTranslation.value(at: p)
        return MoteFrame(center: CGPoint(x: rest.x + d.x, y: rest.y + d.y), opacity: MotionSpec.moteOpacity.value(at: p))
    }
}

/// Sprite de una mota: halo por fuera + relleno translúcido, con el `blur` del elemento.
struct MoteSprite: View {
    let mote: MotionSpec.Mote

    var body: some View {
        ZStack {
            OuterGlow(shape: Circle(), shadows: [mote.glow])
            Circle().fill(mote.fill.color)
        }
        .frame(width: mote.size, height: mote.size)
        .blur(radius: mote.blur)
    }
}

/// Capa de motas a pantalla completa (no recibe toques ni la lee VoiceOver).
struct LightMotesOverlay: View {
    var motes: [MotionSpec.Mote] = MotionSpec.motes
    /// Zonas neutras (en el espacio de esta capa) que las motas no pisan.
    var exclusions: [NeutralZoneRect] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            AmbientTimeline(frameInterval: MotionSpec.moteFrameInterval) { time in
                if let time {
                    ZStack(alignment: .topLeading) {
                        ForEach(motes) { mote in
                            let f = mote.frame(at: time, in: size)
                            MoteSprite(mote: mote)
                                .opacity(f.opacity)
                                .position(f.center)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
            }
        }
        .mask {
            if exclusions.isEmpty {
                Rectangle()
            } else {
                NeutralZoneMask(exclusions: exclusions)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Máscara opaca con agujeros en las zonas neutras (unión: los solapes siguen recortados).
struct NeutralZoneMask: View {
    let exclusions: [NeutralZoneRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
            ForEach(Array(exclusions.enumerated()), id: \.offset) { _, zone in
                RoundedRectangle(cornerRadius: zone.cornerRadius, style: .continuous)
                    .frame(width: zone.rect.width, height: zone.rect.height)
                    .offset(x: zone.rect.minX, y: zone.rect.minY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

extension View {
    /// Pone la capa de motas de luz encima de esta vista, sin tapar sus zonas neutras.
    func lightMotes(motes: [MotionSpec.Mote] = MotionSpec.motes) -> some View {
        overlayPreferenceValue(NeutralZoneKey.self) { anchors in
            GeometryReader { proxy in
                LightMotesOverlay(motes: motes,
                                  exclusions: anchors.map { NeutralZoneRect(rect: proxy[$0.bounds], cornerRadius: $0.cornerRadius) })
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
