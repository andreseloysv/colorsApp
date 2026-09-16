// Dibujo vectorial de los cuatro iconos de pestaña ORIGINALES de ChromaSol (Canvas, viewBox
// 24 × 24 como los SVG del ejemplo, con 4 unidades de margen para el bote y los halos):
//   Feed     semilla solar redonda con carita, rayitos y brote (bota y parpadea)
//   Extraer  libélula de alas translúcidas con lente ámbar (aletea; alas que vibran)
//   Rejilla  gotita de rocío con hoja y reflejo de rejilla 2 × 2 (se mece)
//   Jardín   brote de hojas de corazón en maceta sonriente con yema ámbar (se balancea)
// Personajes propios: sin parecido con criaturas de películas ni videojuegos.
// Solo SwiftUI (sin UIKit).
import SwiftUI

struct BrandTabIconPainter: Sendable {
    let kind: BrandTabIconKind
    let ink: BrandInk
    let pose: TabIconPose

    /// Unidades del lienzo: viewBox 24 más 4 de margen por lado.
    static let canvasUnits: CGFloat = 32
    static let margin: CGFloat = 4

    func draw(_ context: GraphicsContext, size: CGSize) {
        let u = size.width / Self.canvasUnits
        switch kind {
        case .feed: drawSeed(context, u)
        case .extraer: drawDragonfly(context, u)
        case .rejilla: drawDewdrop(context, u)
        case .jardin: drawPottedSprout(context, u)
        }
    }

    // MARK: Utilidades

    /// Contexto en unidades del viewBox (sin transformación del cuerpo).
    private func box(_ context: GraphicsContext, _ u: CGFloat) -> GraphicsContext {
        var c = context
        c.scaleBy(x: u, y: u)
        c.translateBy(x: Self.margin, y: Self.margin)
        return c
    }

    /// Transformación CSS del cuerpo: `translateY(y) scale(sx, sy)` o `rotate(r) translateY(y)`
    /// alrededor de `origin` (en unidades del viewBox), en el orden de la lista CSS.
    private func applyBody(_ c: inout GraphicsContext, origin: CGPoint, rotateFirst: Bool) {
        c.translateBy(x: origin.x, y: origin.y)
        if rotateFirst {
            c.rotate(by: .degrees(pose.rotation))
            c.translateBy(x: 0, y: pose.offsetY)
            c.scaleBy(x: pose.scaleX, y: pose.scaleY)
        } else {
            c.translateBy(x: 0, y: pose.offsetY)
            c.rotate(by: .degrees(pose.rotation))
            c.scaleBy(x: pose.scaleX, y: pose.scaleY)
        }
        c.translateBy(x: -origin.x, y: -origin.y)
    }

    /// Halo difuso (div con `blur`) dibujado en una capa con filtro en puntos.
    private func softGlow(_ context: GraphicsContext, _ u: CGFloat, center: CGPoint, radius: CGFloat,
                          color: Color, blur: CGFloat, bodyOrigin: CGPoint?, rotateFirst: Bool = false) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: blur * u))
            var c = box(layer, u)
            if let bodyOrigin { applyBody(&c, origin: bodyOrigin, rotateFirst: rotateFirst) }
            c.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(color))
        }
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    /// Mota que late: punto fijo + anillo de `animate-ping`.
    private func pingMote(_ c: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        if pose.pingOpacity > 0.001 {
            c.fill(circle(p, r * pose.pingScale), with: .color(color.opacity(pose.pingOpacity)))
        }
        c.fill(circle(p, r), with: .color(color))
    }

    // MARK: Feed: semilla solar

    private func drawSeed(_ context: GraphicsContext, _ u: CGFloat) {
        let origin = CGPoint(x: 12, y: 12)
        // `absolute inset-0 rounded-full bg-amber-400/20 blur-[2px]` (se mueve con el cuerpo).
        softGlow(context, u, center: CGPoint(x: 12, y: 12.6), radius: 11.5, color: ink.sunGold.opacity(0.2), blur: 2, bodyOrigin: origin)
        var c = box(context, u)
        applyBody(&c, origin: origin, rotateFirst: false)
        let center = CGPoint(x: 12, y: 12.9)

        // Rayitos redondeados (sin rayo arriba: ahí nace el brote).
        for i in 0..<8 {
            let angle = (22.5 + Double(i) * 45) * .pi / 180
            let dir = CGPoint(x: sin(angle), y: -cos(angle))
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + dir.x * 9.2, y: center.y + dir.y * 9.0))
            ray.addLine(to: CGPoint(x: center.x + dir.x * 10.9, y: center.y + dir.y * 10.6))
            c.stroke(ray, with: .color(ink.sunAmber), style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
        }

        // Brote de la semilla.
        var stem = Path()
        stem.move(to: CGPoint(x: 12, y: 6.4))
        stem.addQuadCurve(to: CGPoint(x: 12.5, y: 3.4), control: CGPoint(x: 11.7, y: 4.8))
        c.stroke(stem, with: .color(ink.moss), style: StrokeStyle(lineWidth: 0.95, lineCap: .round))
        let right = ChromaSolGeometry.leaf(r0: 0, r1: 3.7, halfWidth: 1.15)
            .applying(CGAffineTransform(rotationAngle: -0.45).concatenating(CGAffineTransform(translationX: 12.45, y: 3.9)))
        let left = ChromaSolGeometry.leaf(r0: 0, r1: 3.0, halfWidth: 0.95)
            .applying(CGAffineTransform(rotationAngle: .pi + 0.5).concatenating(CGAffineTransform(translationX: 12.15, y: 4.9)))
        c.fill(right, with: .color(ink.sage))
        c.stroke(right, with: .color(ink.mossDeep), lineWidth: 0.4)
        c.fill(left, with: .color(ink.moss))

        // Cuerpo dorado.
        let body = ellipse(center, 7.4, 7.0)
        c.fill(body, with: .radialGradient(Gradient(stops: [
            .init(color: ink.sunLight, location: 0), .init(color: ink.sunGold, location: 0.5), .init(color: ink.sunAmber, location: 1),
        ]), center: CGPoint(x: 9.8, y: 10.2), startRadius: 0, endRadius: 10))
        c.stroke(body, with: .color(ink.sunEdge), lineWidth: 0.8)

        // Mejillas y boca.
        c.fill(circle(CGPoint(x: 7.9, y: 15.0), 1.05), with: .color(ink.cheek.opacity(0.5)))
        c.fill(circle(CGPoint(x: 16.1, y: 15.0), 1.05), with: .color(ink.cheek.opacity(0.5)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 10.9, y: 15.4))
        mouth.addQuadCurve(to: CGPoint(x: 13.1, y: 15.4), control: CGPoint(x: 12, y: 16.6))
        c.stroke(mouth, with: .color(ink.face), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

        // Ojos que parpadean (parpadeo 3,4 s: scaleY alrededor del centro de los ojos).
        var eyes = c
        eyes.translateBy(x: 0, y: 12.6)
        eyes.scaleBy(x: 1, y: pose.eyeScaleY)
        eyes.translateBy(x: 0, y: -12.6)
        for x in [9.7, 14.3] as [CGFloat] {
            eyes.fill(ellipse(CGPoint(x: x, y: 12.6), 1.05, 1.3), with: .color(ink.face))
            eyes.fill(circle(CGPoint(x: x + 0.38, y: 12.1), 0.4), with: .color(.white))
        }

        // Chispa dorada que late (`animate-pulse`).
        var spark = box(context, u)
        spark.opacity = pose.sparkOpacity
        spark.fill(ChromaSolGeometry.sparkle(center: CGPoint(x: 19.6, y: 4.4), radius: 1.9), with: .color(ink.sunGold))
    }

    // MARK: Extraer: libélula

    private func drawDragonfly(_ context: GraphicsContext, _ u: CGFloat) {
        let origin = CGPoint(x: 12, y: 12)
        var c = box(context, u)
        applyBody(&c, origin: origin, rotateFirst: true)

        // Alas (`wing-vibrate`: opacidad y scaleY alrededor del centro del viewBox).
        c.drawLayer { layer in
            var wings = layer
            wings.opacity = pose.wingOpacity
            wings.translateBy(x: 12, y: 12)
            wings.scaleBy(x: 1, y: pose.wingScaleY)
            wings.translateBy(x: -12, y: -12)
            func wing(center: CGPoint, rx: CGFloat, ry: CGFloat, angle: Double, fill: Color, stroke: Color, vein: Bool) {
                let t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle * .pi / 180)
                let shape = ellipse(.zero, rx, ry).applying(t)
                wings.fill(shape, with: .color(fill))
                wings.stroke(shape, with: .color(stroke), lineWidth: 0.75)
                if vein {
                    var v = Path()
                    v.move(to: CGPoint(x: -rx * 0.8, y: 0))
                    v.addLine(to: CGPoint(x: rx * 0.8, y: 0))
                    wings.stroke(v.applying(t), with: .color(stroke.opacity(0.5)), lineWidth: 0.35)
                }
            }
            wing(center: CGPoint(x: 6.6, y: 8.3), rx: 5.3, ry: 2.15, angle: -16, fill: ink.celadonPale, stroke: ink.celadonInk, vein: true)
            wing(center: CGPoint(x: 17.4, y: 8.3), rx: 5.3, ry: 2.15, angle: 16, fill: ink.celadonPale, stroke: ink.celadonInk, vein: true)
            wing(center: CGPoint(x: 7.2, y: 12.0), rx: 4.5, ry: 1.8, angle: 12, fill: ink.peach, stroke: ink.amberInk, vein: false)
            wing(center: CGPoint(x: 16.8, y: 12.0), rx: 4.5, ry: 1.8, angle: -12, fill: ink.peach, stroke: ink.amberInk, vein: false)
        }

        // Abdomen afilado con anillos ámbar.
        var abdomen = Path()
        abdomen.move(to: CGPoint(x: 10.75, y: 10.6))
        abdomen.addCurve(to: CGPoint(x: 11.55, y: 20.9), control1: CGPoint(x: 10.7, y: 14), control2: CGPoint(x: 11.1, y: 18.5))
        abdomen.addQuadCurve(to: CGPoint(x: 12.45, y: 20.9), control: CGPoint(x: 12, y: 21.9))
        abdomen.addCurve(to: CGPoint(x: 13.25, y: 10.6), control1: CGPoint(x: 12.9, y: 18.5), control2: CGPoint(x: 13.3, y: 14))
        abdomen.closeSubpath()
        c.fill(abdomen, with: .color(ink.moss))
        var bands = c
        bands.clip(to: abdomen)
        for y in [13.3, 15.8, 18.2] as [CGFloat] {
            var band = Path()
            band.move(to: CGPoint(x: 10.5, y: y))
            band.addLine(to: CGPoint(x: 13.5, y: y))
            bands.stroke(band, with: .color(ink.sunAmber), lineWidth: 0.85)
        }

        // Tórax con lente ámbar.
        c.fill(ellipse(CGPoint(x: 12, y: 9.1), 2.05, 2.35), with: .color(ink.mossDeep))
        c.fill(circle(CGPoint(x: 12, y: 9.1), 0.95), with: .color(ink.sunGold))
        c.fill(circle(CGPoint(x: 11.7, y: 8.8), 0.32), with: .color(.white.opacity(0.9)))

        // Cabeza: ojos compuestos con brillo y sonrisa.
        for x in [10.85, 13.15] as [CGFloat] {
            let eye = circle(CGPoint(x: x, y: 5.7), 1.65)
            c.fill(eye, with: .color(ink.celadon))
            c.stroke(eye, with: .color(ink.celadonInk), lineWidth: 0.5)
            c.fill(circle(CGPoint(x: x - 0.45, y: 5.2), 0.52), with: .color(.white))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: 11.35, y: 7.25))
        smile.addQuadCurve(to: CGPoint(x: 12.65, y: 7.25), control: CGPoint(x: 12, y: 7.85))
        c.stroke(smile, with: .color(ink.face), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
    }

    // MARK: Rejilla: gotita de rocío

    private func drawDewdrop(_ context: GraphicsContext, _ u: CGFloat) {
        let origin = CGPoint(x: 12, y: 24)
        // `absolute -top-1 w-5 h-5 rounded-full bg-emerald-300/30 blur-[3px]` (fijo, no se mece).
        softGlow(context, u, center: CGPoint(x: 12, y: 7), radius: 7.5, color: Color(brand: 0x6EE7B7, opacity: 0.3), blur: 3, bodyOrigin: nil)
        var c = box(context, u)
        applyBody(&c, origin: origin, rotateFirst: true)

        var drop = Path()
        drop.move(to: CGPoint(x: 12, y: 3.4))
        drop.addCurve(to: CGPoint(x: 18.3, y: 14.4), control1: CGPoint(x: 13.3, y: 5.9), control2: CGPoint(x: 18.3, y: 9.6))
        drop.addCurve(to: CGPoint(x: 12, y: 21.0), control1: CGPoint(x: 18.3, y: 18.1), control2: CGPoint(x: 15.5, y: 21.0))
        drop.addCurve(to: CGPoint(x: 5.7, y: 14.4), control1: CGPoint(x: 8.5, y: 21.0), control2: CGPoint(x: 5.7, y: 18.1))
        drop.addCurve(to: CGPoint(x: 12, y: 3.4), control1: CGPoint(x: 5.7, y: 9.6), control2: CGPoint(x: 10.7, y: 5.9))
        drop.closeSubpath()

        // Hoja que brota de la punta (detrás del contorno).
        let leaf = ChromaSolGeometry.leaf(r0: 0, r1: 4.6, halfWidth: 1.35)
            .applying(CGAffineTransform(rotationAngle: -0.42).concatenating(CGAffineTransform(translationX: 12.1, y: 3.9)))
        c.fill(leaf, with: .color(ink.sage))
        c.stroke(leaf, with: .color(ink.mossDeep), lineWidth: 0.4)

        c.fill(drop, with: .linearGradient(Gradient(colors: [Color(brand: 0xECFBF5), ink.celadonPale, Color(brand: 0x8CC7B5)]),
                                           startPoint: CGPoint(x: 9, y: 6), endPoint: CGPoint(x: 15, y: 21)))
        c.stroke(drop, with: .color(ink.celadonInk), lineWidth: 0.8)

        // Reflejo en forma de rejilla 2 × 2 (guiño a las 348 combinaciones).
        let cell: CGFloat = 1.5, gap: CGFloat = 0.5
        for row in 0..<2 {
            for col in 0..<2 {
                let r = CGRect(x: 8.0 + CGFloat(col) * (cell + gap), y: 9.4 + CGFloat(row) * (cell + gap), width: cell, height: cell)
                c.fill(Path(roundedRect: r, cornerRadius: 0.35), with: .color(.white.opacity(0.92)))
            }
        }

        // Carita (tres cuartos, desplazada a la derecha del reflejo).
        c.fill(circle(CGPoint(x: 9.5, y: 17.0), 0.9), with: .color(ink.cheek.opacity(0.42)))
        c.fill(circle(CGPoint(x: 15.6, y: 17.0), 0.9), with: .color(ink.cheek.opacity(0.42)))
        for x in [10.8, 14.2] as [CGFloat] {
            c.fill(ellipse(CGPoint(x: x, y: 15.3), 0.75, 0.95), with: .color(ink.faceCool))
            c.fill(circle(CGPoint(x: x + 0.25, y: 14.95), 0.28), with: .color(.white))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: 11.6, y: 17.1))
        smile.addQuadCurve(to: CGPoint(x: 13.4, y: 17.1), control: CGPoint(x: 12.5, y: 18.0))
        c.stroke(smile, with: .color(ink.faceCool), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))

        // Mota verde que late (`animate-ping`), fuera del cuerpo.
        var mote = box(context, u)
        pingMote(&mote, at: CGPoint(x: 18.6, y: 4.6), radius: 0.95, color: ink.mint)
    }

    // MARK: Jardín: brote en maceta

    private func drawPottedSprout(_ context: GraphicsContext, _ u: CGFloat) {
        let origin = CGPoint(x: 12, y: 24)
        // `absolute inset-0 rounded-full bg-emerald-400/20 blur-[2px]` (se balancea con todo).
        softGlow(context, u, center: CGPoint(x: 12, y: 12), radius: 11.5, color: Color(brand: 0x34D399, opacity: 0.2), blur: 2,
                 bodyOrigin: origin, rotateFirst: true)
        var c = box(context, u)
        applyBody(&c, origin: origin, rotateFirst: true)

        // Tallo y hojas de corazón.
        var stem = Path()
        stem.move(to: CGPoint(x: 12, y: 13.2))
        stem.addCurve(to: CGPoint(x: 12, y: 7.6), control1: CGPoint(x: 12.05, y: 11.3), control2: CGPoint(x: 11.7, y: 9.6))
        c.stroke(stem, with: .color(ink.moss), style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
        var left = Path()
        left.move(to: CGPoint(x: 11.9, y: 10.4))
        left.addCurve(to: CGPoint(x: 7.2, y: 10.7), control1: CGPoint(x: 10.2, y: 8.0), control2: CGPoint(x: 6.9, y: 8.3))
        left.addCurve(to: CGPoint(x: 11.9, y: 10.4), control1: CGPoint(x: 7.5, y: 12.4), control2: CGPoint(x: 10.5, y: 12.1))
        left.closeSubpath()
        var right = Path()
        right.move(to: CGPoint(x: 12.0, y: 8.9))
        right.addCurve(to: CGPoint(x: 16.9, y: 9.4), control1: CGPoint(x: 13.9, y: 6.4), control2: CGPoint(x: 17.3, y: 6.9))
        right.addCurve(to: CGPoint(x: 12.0, y: 8.9), control1: CGPoint(x: 16.5, y: 11.2), control2: CGPoint(x: 13.4, y: 10.9))
        right.closeSubpath()
        c.fill(left, with: .color(ink.sage))
        c.stroke(left, with: .color(ink.mossDeep), lineWidth: 0.55)
        c.fill(right, with: .color(ink.mint))
        c.stroke(right, with: .color(ink.mossDeep), lineWidth: 0.55)

        // Yema ámbar con latido (`animate-ping`).
        pingMote(&c, at: CGPoint(x: 12, y: 6.5), radius: 1.05, color: ink.sunGold)

        // Maceta de terracota con carita.
        var pot = Path()
        pot.move(to: CGPoint(x: 7.7, y: 14.6))
        pot.addLine(to: CGPoint(x: 16.3, y: 14.6))
        pot.addLine(to: CGPoint(x: 15.1, y: 20.7))
        pot.addQuadCurve(to: CGPoint(x: 14.2, y: 21.5), control: CGPoint(x: 14.95, y: 21.5))
        pot.addLine(to: CGPoint(x: 9.8, y: 21.5))
        pot.addQuadCurve(to: CGPoint(x: 8.9, y: 20.7), control: CGPoint(x: 9.05, y: 21.5))
        pot.closeSubpath()
        c.fill(pot, with: .color(ink.terracotta))
        c.stroke(pot, with: .color(ink.clayInk), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
        let rim = Path(roundedRect: CGRect(x: 6.9, y: 13.0, width: 10.2, height: 2.3), cornerRadius: 1.15)
        c.fill(rim, with: .color(ink.terracottaLight))
        c.stroke(rim, with: .color(ink.clayInk), lineWidth: 0.6)
        c.fill(circle(CGPoint(x: 9.7, y: 18.4), 0.75), with: .color(ink.peach.opacity(0.55)))
        c.fill(circle(CGPoint(x: 14.3, y: 18.4), 0.75), with: .color(ink.peach.opacity(0.55)))
        c.fill(circle(CGPoint(x: 10.8, y: 17.2), 0.58), with: .color(.white))
        c.fill(circle(CGPoint(x: 13.2, y: 17.2), 0.58), with: .color(.white))
        var smile = Path()
        smile.move(to: CGPoint(x: 11.3, y: 18.6))
        smile.addQuadCurve(to: CGPoint(x: 12.7, y: 18.6), control: CGPoint(x: 12, y: 19.3))
        c.stroke(smile, with: .color(.white), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
    }
}

/// Un fotograma de un icono de pestaña (sin reloj): útil para tests y capturas.
struct BrandTabIconFrame: View {
    let kind: BrandTabIconKind
    var pose: TabIconPose = .rest
    /// Lado del dibujo (el viewBox de 24); el lienzo mide 32/24 de este lado.
    var size: CGFloat = 26
    var scheme: ColorScheme?

    @Environment(\.colorScheme) private var environmentScheme

    var body: some View {
        let side = size * BrandTabIconPainter.canvasUnits / 24
        let painter = BrandTabIconPainter(kind: kind, ink: BrandInk(scheme ?? environmentScheme), pose: pose)
        Canvas { ctx, canvasSize in painter.draw(ctx, size: canvasSize) }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
