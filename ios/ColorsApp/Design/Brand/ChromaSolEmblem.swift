// Emblema ORIGINAL de ChromaSol (vectorial, SwiftUI Canvas): una ventana en arco de
// pergamino con filo de latón; dentro, un sol cuyos rayos son hojas (sol + hoja) con una
// rueda de color de seis gajos en el núcleo, un prisma que abre un abanico de espectro y
// un prado al amanecer con un brote. Se inspira en el tono del logotipo del ejemplo
// (arco, sol vegetal, haz de color) sin copiar su dibujo.
// Tres estilos: `.full` (64 pt o más), `.compact` (cabecera, 32 pt: menos piezas y trazos
// más gruesos) y `.appIcon` (a sangre, 1024 px, lo usa ios/Scripts/render_app_icon.swift).
// Solo SwiftUI y CoreGraphics (sin UIKit): compila también en macOS.
import SwiftUI

enum ChromaSolEmblemStyle: String, CaseIterable, Sendable {
    case full, compact, appIcon
}

/// Geometría del emblema en un espacio de 100 × 100 unidades.
struct ChromaSolGeometry: Sendable {
    let style: ChromaSolEmblemStyle

    /// Centro del sol (unidades) y como `UnitPoint` (ancla de la rotación).
    var sunCenter: CGPoint {
        switch style {
        case .full: CGPoint(x: 50, y: 46)
        case .compact: CGPoint(x: 50, y: 47)
        case .appIcon: CGPoint(x: 50, y: 47)
        }
    }
    var sunAnchor: UnitPoint { UnitPoint(x: sunCenter.x / 100, y: sunCenter.y / 100) }

    /// Escala de las piezas del sol respecto a `.full`.
    var sunScale: CGFloat {
        switch style {
        case .full: 0.8
        case .compact: 0.9
        case .appIcon: 0.84
        }
    }

    var leafCount: Int { style == .compact ? 8 : 12 }
    var spikeCount: Int { style == .compact ? 8 : 12 }

    /// Arco exterior (badge). En `.appIcon` el arco es la ventana dentro del icono.
    func arch(inset: CGFloat = 0) -> Path {
        let left: CGFloat, right: CGFloat, springY: CGFloat, bottom: CGFloat, corner: CGFloat
        switch style {
        case .full, .compact:
            left = 11; right = 89; springY = 47; bottom = 97; corner = 7
        case .appIcon:
            left = 12; right = 88; springY = 48; bottom = 112; corner = 0
        }
        let l = left + inset, r = right - inset, b = bottom - inset
        let radius = (r - l) / 2
        let cr = max(corner - inset, 0)
        var p = Path()
        p.move(to: CGPoint(x: l, y: b - cr))
        p.addLine(to: CGPoint(x: l, y: springY))
        p.addRelativeArc(center: CGPoint(x: 50, y: springY), radius: radius,
                         startAngle: .degrees(180), delta: .degrees(180))
        p.addLine(to: CGPoint(x: r, y: b - cr))
        if cr > 0 {
            p.addQuadCurve(to: CGPoint(x: r - cr, y: b), control: CGPoint(x: r, y: b))
            p.addLine(to: CGPoint(x: l + cr, y: b))
            p.addQuadCurve(to: CGPoint(x: l, y: b - cr), control: CGPoint(x: l, y: b))
        } else {
            p.addLine(to: CGPoint(x: l, y: b))
        }
        p.closeSubpath()
        return p
    }

    /// Interior recortable (dentro del filo de latón).
    var interior: Path {
        switch style {
        case .full: arch(inset: 2.2)
        case .compact: arch(inset: 2.8)
        case .appIcon: arch(inset: 1.6)
        }
    }

    /// Hoja con forma de vesica apuntando a +x, de r0 a r1 con semiancho w.
    static func leaf(r0: CGFloat, r1: CGFloat, halfWidth w: CGFloat) -> Path {
        let len = r1 - r0
        var p = Path()
        p.move(to: CGPoint(x: r0, y: 0))
        p.addCurve(to: CGPoint(x: r1, y: 0), control1: CGPoint(x: r0 + len * 0.22, y: -w * 1.35),
                   control2: CGPoint(x: r0 + len * 0.72, y: -w * 1.05))
        p.addCurve(to: CGPoint(x: r0, y: 0), control1: CGPoint(x: r0 + len * 0.72, y: w * 1.05),
                   control2: CGPoint(x: r0 + len * 0.22, y: w * 1.35))
        p.closeSubpath()
        return p
    }

    /// Estrella de cuatro puntas (destellos del cielo).
    static func sparkle(center c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        let k = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

/// Pintor por capas. Todas las capas dibujan en unidades de 100 × 100.
struct ChromaSolPainter: Sendable {
    let style: ChromaSolEmblemStyle
    let ink: BrandInk
    var geo: ChromaSolGeometry { ChromaSolGeometry(style: style) }

    private func unitSpace(_ ctx: inout GraphicsContext, _ size: CGSize) {
        ctx.scaleBy(x: size.width / 100, y: size.height / 100)
    }

    // MARK: Capa 1: marco y cielo

    func drawBackdrop(_ context: GraphicsContext, size: CGSize) {
        var ctx = context
        unitSpace(&ctx, size)
        let interior = geo.interior
        if style == .appIcon {
            // Fondo del icono: seto de musgo con luz cálida arriba.
            let frame = Path(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.fill(frame, with: .linearGradient(
                Gradient(colors: ink.dark ? [Color(brand: 0x1E3A28), Color(brand: 0x0E2216)]
                                          : [Color(brand: 0x3B6849), Color(brand: 0x1B4A2E)]),
                startPoint: CGPoint(x: 50, y: 0), endPoint: CGPoint(x: 50, y: 100)))
            ctx.fill(frame, with: .radialGradient(
                Gradient(colors: [Color(brand: 0xFBBF24, opacity: ink.dark ? 0.22 : 0.30), Color(brand: 0xFBBF24, opacity: 0)]),
                center: CGPoint(x: 50, y: 40), startRadius: 0, endRadius: 62))
            // Sombra suave de la ventana sobre el seto.
            var shadow = ctx
            shadow.addFilter(.blur(radius: 2.4))
            shadow.fill(geo.arch(inset: -1.2).offsetBy(dx: 0, dy: 1.4), with: .color(.black.opacity(0.28)))
        }
        let outer = geo.arch()
        ctx.fill(outer, with: .linearGradient(Gradient(colors: [ink.parchmentTop, ink.parchmentBottom]),
                                              startPoint: CGPoint(x: 50, y: 8), endPoint: CGPoint(x: 50, y: 96)))
        var sky = ctx
        sky.clip(to: interior)
        let c = geo.sunCenter
        sky.fill(interior, with: .radialGradient(Gradient(colors: [ink.skyGlow, ink.skyGlow.opacity(0)]),
                                                 center: c, startRadius: 0, endRadius: 40 * geo.sunScale))
        if style != .compact {
            let stars: [(CGPoint, CGFloat)] = style == .appIcon
                ? [(CGPoint(x: 24, y: 30), 2.6), (CGPoint(x: 77, y: 24), 2.1), (CGPoint(x: 81, y: 44), 1.4)]
                : [(CGPoint(x: 23, y: 31), 2.8), (CGPoint(x: 77, y: 24), 2.2)]
            for (p, r) in stars {
                sky.fill(ChromaSolGeometry.sparkle(center: p, radius: r), with: .color(ink.sunGold.opacity(0.9)))
            }
        }
    }

    // MARK: Capa 2: sol (rayos-hoja, puntas ámbar, núcleo con rueda de color). Gira.

    func drawSun(_ context: GraphicsContext, size: CGSize) {
        var ctx = context
        unitSpace(&ctx, size)
        let c = geo.sunCenter
        let s = geo.sunScale
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: s, y: s)
        let compact = style == .compact

        // Puntas ámbar entre hojas.
        let spikes = geo.spikeCount
        for i in 0..<spikes {
            let angle = (Double(i) + 0.5) / Double(spikes) * 2 * .pi
            var spike = Path()
            let r0: CGFloat = 13, r1: CGFloat = compact ? 30 : 31, half: CGFloat = compact ? 4.2 : 2.9
            spike.move(to: CGPoint(x: r0, y: -half))
            spike.addLine(to: CGPoint(x: r1, y: 0))
            spike.addLine(to: CGPoint(x: r0, y: half))
            spike.closeSubpath()
            ctx.fill(spike.applying(CGAffineTransform(rotationAngle: angle)), with: .color(ink.sunAmber))
        }

        // Hojas-rayo, alternando musgo y salvia, con nervio claro.
        let leaves = geo.leafCount
        for i in 0..<leaves {
            let angle = Double(i) / Double(leaves) * 2 * .pi - .pi / 2
            let t = CGAffineTransform(rotationAngle: angle)
            let leaf = ChromaSolGeometry.leaf(r0: 14, r1: compact ? 35 : 34, halfWidth: compact ? 5.6 : 3.9).applying(t)
            let fill = i.isMultiple(of: 2) ? ink.moss : ink.sage
            ctx.fill(leaf, with: .color(fill))
            if !compact {
                var rib = Path()
                rib.move(to: CGPoint(x: 16, y: 0))
                rib.addLine(to: CGPoint(x: 30, y: 0))
                ctx.stroke(rib.applying(t), with: .color(ink.sunLight.opacity(0.55)), lineWidth: 0.6)
                ctx.stroke(leaf, with: .color(ink.mossDeep.opacity(0.35)), lineWidth: 0.5)
            }
        }

        // Núcleo solar.
        let coreR: CGFloat = compact ? 15.5 : 14.5
        let core = Path(ellipseIn: CGRect(x: -coreR, y: -coreR, width: coreR * 2, height: coreR * 2))
        ctx.fill(core, with: .radialGradient(Gradient(stops: [
            .init(color: ink.sunLight, location: 0), .init(color: ink.sunGold, location: 0.55), .init(color: ink.sunAmber, location: 1),
        ]), center: CGPoint(x: -4, y: -4), startRadius: 0, endRadius: coreR * 1.5))
        ctx.stroke(core, with: .color(ink.sunDeep), lineWidth: compact ? 1.6 : 1.1)

        // Rueda de color de seis gajos.
        let wheelR: CGFloat = compact ? 10.5 : 9.6
        let colors = ink.wheel
        for (i, color) in colors.enumerated() {
            var wedge = Path()
            wedge.move(to: .zero)
            wedge.addRelativeArc(center: .zero, radius: wheelR, startAngle: .degrees(Double(i) * 60 - 90), delta: .degrees(60))
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(color))
        }
        for i in 0..<colors.count {
            var sep = Path()
            sep.move(to: .zero)
            let a = Double(i) * 60 - 90
            sep.addLine(to: CGPoint(x: cos(a * .pi / 180) * wheelR, y: sin(a * .pi / 180) * wheelR))
            ctx.stroke(sep, with: .color(ink.sunLight), lineWidth: compact ? 1.2 : 0.9)
        }
        let wheel = Path(ellipseIn: CGRect(x: -wheelR, y: -wheelR, width: wheelR * 2, height: wheelR * 2))
        ctx.stroke(wheel, with: .color(ink.sunLight), lineWidth: compact ? 1.2 : 0.9)
        let hubR: CGFloat = compact ? 3.2 : 2.6
        let hub = Path(ellipseIn: CGRect(x: -hubR, y: -hubR, width: hubR * 2, height: hubR * 2))
        ctx.fill(hub, with: .color(ink.sunLight))
        ctx.stroke(hub, with: .color(ink.sunDeep.opacity(0.8)), lineWidth: 0.5)
    }

    // MARK: Capa 3: prado, prisma con abanico de espectro, brote y filo de latón

    func drawForeground(_ context: GraphicsContext, size: CGSize) {
        var ctx = context
        unitSpace(&ctx, size)
        let compact = style == .compact
        let appIcon = style == .appIcon
        var inside = ctx
        inside.clip(to: geo.interior)

        // Prado: colina de fondo.
        var back = Path()
        var front = Path()
        if compact {
            back.move(to: CGPoint(x: 0, y: 81))
            back.addCurve(to: CGPoint(x: 100, y: 77), control1: CGPoint(x: 30, y: 71), control2: CGPoint(x: 65, y: 87))
            front.move(to: CGPoint(x: 0, y: 91))
            front.addCurve(to: CGPoint(x: 100, y: 87), control1: CGPoint(x: 35, y: 81), control2: CGPoint(x: 70, y: 95))
        } else {
            back.move(to: CGPoint(x: 0, y: 80))
            back.addCurve(to: CGPoint(x: 58, y: 78), control1: CGPoint(x: 20, y: 71), control2: CGPoint(x: 42, y: 72))
            back.addCurve(to: CGPoint(x: 100, y: 73), control1: CGPoint(x: 72, y: 83), control2: CGPoint(x: 86, y: 77))
            front.move(to: CGPoint(x: 0, y: 89))
            front.addCurve(to: CGPoint(x: 53, y: 87), control1: CGPoint(x: 20, y: 81), control2: CGPoint(x: 40, y: 82))
            front.addCurve(to: CGPoint(x: 100, y: 85), control1: CGPoint(x: 68, y: 92), control2: CGPoint(x: 84, y: 88))
        }
        back.addLine(to: CGPoint(x: 100, y: 120)); back.addLine(to: CGPoint(x: 0, y: 120)); back.closeSubpath()
        front.addLine(to: CGPoint(x: 100, y: 120)); front.addLine(to: CGPoint(x: 0, y: 120)); front.closeSubpath()
        inside.fill(back, with: .color(ink.hillBack))

        // Prisma de cristal: el rayo del sol entra por la cara izquierda y sale en abanico.
        let prism: (top: CGPoint, left: CGPoint, right: CGPoint)
        switch style {
        case .full: prism = (CGPoint(x: 69, y: 62), CGPoint(x: 60, y: 77), CGPoint(x: 78, y: 77))
        case .compact: prism = (CGPoint(x: 70, y: 62), CGPoint(x: 59, y: 80), CGPoint(x: 81, y: 80))
        case .appIcon: prism = (CGPoint(x: 69, y: 64), CGPoint(x: 60, y: 79), CGPoint(x: 78, y: 79))
        }
        let edgeX: CGFloat = 94
        let exitTop = CGPoint(x: prism.top.x + (prism.right.x - prism.top.x) * 0.35, y: prism.top.y + (prism.right.y - prism.top.y) * 0.35)
        let exitBottom = CGPoint(x: prism.top.x + (prism.right.x - prism.top.x) * 0.62, y: prism.top.y + (prism.right.y - prism.top.y) * 0.62)
        let bands = ink.spectrum
        let fanTop: CGFloat = compact ? 56 : 57, fanBottom: CGFloat = compact ? 90 : 86
        let step = (fanBottom - fanTop) / CGFloat(bands.count)
        for (i, color) in bands.enumerated() {
            let f0 = CGFloat(i) / CGFloat(bands.count), f1 = CGFloat(i + 1) / CGFloat(bands.count)
            func exit(_ f: CGFloat) -> CGPoint {
                CGPoint(x: exitTop.x + (exitBottom.x - exitTop.x) * f, y: exitTop.y + (exitBottom.y - exitTop.y) * f)
            }
            var band = Path()
            band.move(to: exit(f0))
            band.addLine(to: CGPoint(x: edgeX, y: fanTop + CGFloat(i) * step))
            band.addLine(to: CGPoint(x: edgeX, y: fanTop + CGFloat(i + 1) * step))
            band.addLine(to: exit(f1))
            band.closeSubpath()
            inside.fill(band, with: .color(color.opacity(0.9)))
        }
        var tri = Path()
        tri.move(to: prism.top)
        tri.addLine(to: prism.right)
        tri.addLine(to: prism.left)
        tri.closeSubpath()
        inside.fill(tri, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.92), Color(brand: 0xBDECDC, opacity: 0.82)]),
                                               startPoint: prism.top, endPoint: CGPoint(x: prism.top.x, y: prism.left.y)))
        var facet = Path()
        facet.move(to: prism.top)
        facet.addLine(to: CGPoint(x: (prism.left.x + prism.right.x) / 2 - 1.5, y: prism.left.y))
        inside.stroke(facet, with: .color(Color.white.opacity(0.7)), lineWidth: compact ? 1.0 : 0.6)
        inside.stroke(tri, with: .color(ink.brass), style: StrokeStyle(lineWidth: compact ? 1.5 : 1.0, lineJoin: .round))

        // Prado: colina de delante.
        inside.fill(front, with: .color(ink.hillFront))

        if !compact {
            // Brote que asoma entre las dos colinas.
            let base = CGPoint(x: 27, y: 87.5)
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: CGPoint(x: 27.6, y: 78.5), control: CGPoint(x: 26, y: 83))
            inside.stroke(stem, with: .color(ink.moss), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            let leftLeaf = ChromaSolGeometry.leaf(r0: 0, r1: 7, halfWidth: 2.1)
                .applying(CGAffineTransform(rotationAngle: .pi + 0.5).concatenating(CGAffineTransform(translationX: 27.3, y: 81)))
            let rightLeaf = ChromaSolGeometry.leaf(r0: 0, r1: 7.8, halfWidth: 2.4)
                .applying(CGAffineTransform(rotationAngle: -0.6).concatenating(CGAffineTransform(translationX: 27.6, y: 79)))
            inside.fill(leftLeaf, with: .color(ink.sage))
            inside.fill(rightLeaf, with: .color(ink.mintPale))
            inside.stroke(leftLeaf, with: .color(ink.mossDeep.opacity(0.8)), lineWidth: 0.5)
            inside.stroke(rightLeaf, with: .color(ink.mossDeep.opacity(0.8)), lineWidth: 0.5)
            // Luciérnagas del prado.
            for (p, r) in [(CGPoint(x: 44, y: 92), 0.9), (CGPoint(x: 64, y: 95), 0.7), (CGPoint(x: 18, y: 93), 0.6)] as [(CGPoint, CGFloat)] {
                inside.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(ink.sunGold))
            }
        }

        // Filo de latón (y línea interior en los estilos grandes).
        let outer = geo.arch()
        ctx.stroke(outer, with: .color(ink.brass), style: StrokeStyle(lineWidth: compact ? 3.2 : (appIcon ? 2.4 : 2.2), lineJoin: .round))
        if !compact {
            ctx.stroke(geo.arch(inset: appIcon ? 4.2 : 4.4), with: .color(ink.brass.opacity(appIcon ? 0.5 : 0.42)), lineWidth: 0.7)
        }
    }
}

/// Emblema de ChromaSol a cualquier tamaño (cuadrado). `sun` gira y hace brillar el sol
/// (pose de `BrandMotion.sparkle`); en reposo es estático. El resplandor ámbar va en el
/// marco (logotipo), nunca junto a un swatch.
struct ChromaSolEmblem: View {
    var style: ChromaSolEmblemStyle = .full
    var sun: SunSparklePose = .rest
    /// Fuerza un tema (icono de la app); nil = el del entorno.
    var scheme: ColorScheme?
    /// Dibuja el resplandor del destello (desactivar para el icono de la app).
    var glow: Bool = true

    @Environment(\.colorScheme) private var environmentScheme

    var body: some View {
        let painter = ChromaSolPainter(style: style, ink: BrandInk(scheme ?? environmentScheme))
        let geo = painter.geo
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                EmblemLayer(painter: painter, layer: .backdrop).equatable()
                EmblemLayer(painter: painter, layer: .sun).equatable()
                    .scaleEffect(sun.scale, anchor: geo.sunAnchor)
                    .rotationEffect(.degrees(sun.rotation), anchor: geo.sunAnchor)
                    .shadow(color: glow ? painter.ink.sunGlow.opacity(sun.glowOpacity) : .clear,
                            radius: glow ? sun.glowBlur / 2 * side / 64 : 0)
                    .mask { geo.interior.applying(CGAffineTransform(scaleX: side / 100, y: side / 100)) }
                EmblemLayer(painter: painter, layer: .foreground).equatable()
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Capa estática del emblema (equatable: no se vuelve a pintar mientras el sol gira).
private struct EmblemLayer: View, Equatable {
    enum Layer { case backdrop, sun, foreground }
    let painter: ChromaSolPainter
    let layer: Layer

    nonisolated static func == (a: EmblemLayer, b: EmblemLayer) -> Bool {
        a.layer == b.layer && a.painter.style == b.painter.style && a.painter.ink.dark == b.painter.ink.dark
    }

    var body: some View {
        Canvas { ctx, size in
            switch layer {
            case .backdrop: painter.drawBackdrop(ctx, size: size)
            case .sun: painter.drawSun(ctx, size: size)
            case .foreground: painter.drawForeground(ctx, size: size)
            }
        }
    }
}
