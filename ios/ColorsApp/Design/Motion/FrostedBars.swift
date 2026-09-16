// Barras esmeriladas del ejemplo con sus luces exactas:
//   cabecera   `bg-surface/85 backdrop-blur-xl shadow-[0_1px_14px_rgba(234,179,8,0.1)] border-b border-amber-500/10`
//   pestañas   `bg-surface/90 backdrop-blur-xl shadow-[0_-3px_16px_rgba(234,179,8,0.12)] border-t border-amber-500/15`
// Material del sistema (desenfoque del fondo) + tinte `surface` + sombra ámbar + filo ámbar
// de 1 pt. Estáticas: no animan ni consumen CPU en reposo. Sin materiales en celdas.
import SwiftUI

/// Fondo esmerilado de una barra (cabecera o pestañas).
struct FrostedBarBackground: View {
    let spec: MotionSpec.FrostedBar
    /// Borde donde va el filo ámbar (`.bottom` en la cabecera, `.top` en las pestañas).
    let hairlineEdge: VerticalEdge
    /// Extiende el fondo bajo el área segura del lado del filo contrario.
    var extendsIntoSafeArea: Bool = true

    var body: some View {
        ZStack(alignment: hairlineEdge == .bottom ? .bottom : .top) {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.surface.opacity(spec.tintOpacity))
            Rectangle().fill(spec.hairline.color).frame(height: 1)
        }
        .compositingGroup()
        .shadow(color: spec.shadow.color.color, radius: spec.shadow.radius, x: 0, y: CGFloat(spec.shadow.y))
        .ignoresSafeArea(edges: extendsIntoSafeArea ? (hairlineEdge == .bottom ? .top : .bottom) : [])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Cabecera: material + `surface` 85 % + sombra `0 1px 14px` ámbar 10 % + filo inferior ámbar 10 %.
/// Uso: `.background { FrostedHeaderBackground() }`.
struct FrostedHeaderBackground: View {
    var extendsIntoSafeArea: Bool = true

    var body: some View {
        FrostedBarBackground(spec: MotionSpec.header, hairlineEdge: .bottom, extendsIntoSafeArea: extendsIntoSafeArea)
    }
}

/// Barra de pestañas: material + `surface` 90 % + sombra `0 -3px 16px` ámbar 12 % + filo superior ámbar 15 %.
struct FrostedTabBarBackground: View {
    var extendsIntoSafeArea: Bool = true

    var body: some View {
        FrostedBarBackground(spec: MotionSpec.tabBar, hairlineEdge: .top, extendsIntoSafeArea: extendsIntoSafeArea)
    }
}
