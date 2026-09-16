// Referencia de geometría de los personajes, el logotipo y el sol de cabecera ORIGINALES
// (docs/design/FIDELITY.md §2). Script de macOS: dibuja con GraphicsContext (misma API que
// Canvas en iOS) y guarda creatures.png. No se compila en la app (docs/ no está en project.yml).
// Regenerar: swiftc -O -parse-as-library -o /tmp/x original-characters.swift && /tmp/x
// (escribe creatures.png en el directorio actual). Viewbox 24×24 (logo 28×32, sol 32×32).
import SwiftUI
import AppKit

extension Color {
    init(_ hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: a)
    }
}

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rot: Double = 0) -> Path {
    Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
        .applying(CGAffineTransform(rotationAngle: rot * .pi / 180).concatenating(CGAffineTransform(translationX: cx, y: cy)))
}
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path { ellipse(cx, cy, r, r) }

/// Pose genérica: rotación (grados) y desplazamiento alrededor de un origen.
struct Pose { var rot: Double = 0; var dy: CGFloat = 0; var sx: CGFloat = 1; var sy: CGFloat = 1; var eyes: CGFloat = 1; var wings: CGFloat = 1; var wingAlpha: Double = 0.7 }

func withPose(_ ctx: inout GraphicsContext, origin: CGPoint, _ p: Pose) {
    ctx.translateBy(x: origin.x, y: origin.y + p.dy)
    ctx.rotate(by: .degrees(p.rot))
    ctx.scaleBy(x: p.sx, y: p.sy)
    ctx.translateBy(x: -origin.x, y: -origin.y)
}

// 1. Feed: semilla solar
func drawSeed(_ c: GraphicsContext, _ p: Pose) {
    var ctx = c
    withPose(&ctx, origin: CGPoint(x: 12, y: 12.5), p)
    for k in 1..<8 {
        let a = Double(k) * 45 - 90
        let x = 12 + 8.4 * cos(a * .pi / 180), y = 12.5 + 8.4 * sin(a * .pi / 180)
        ctx.fill(ellipse(x, y, 1.5, 2.5, rot: a + 90), with: .color(k % 2 == 0 ? Color(0xF59E0B) : Color(0xFBBF24)))
    }
    ctx.stroke(Path { $0.move(to: CGPoint(x: 12, y: 6.2)); $0.addQuadCurve(to: CGPoint(x: 13.4, y: 3.9), control: CGPoint(x: 12.1, y: 4.6)) }, with: .color(Color(0x2D5A3C)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
    ctx.fill(ellipse(15, 3.7, 2.1, 1.0, rot: -20), with: .color(Color(0x81B29A)))
    ctx.stroke(ellipse(15, 3.7, 2.1, 1.0, rot: -20), with: .color(Color(0x2D5A3C)), lineWidth: 0.45)
    let body = circle(12, 12.5, 6.8)
    ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(0xFEF08A), Color(0xFBBF24), Color(0xF59E0B)]), center: CGPoint(x: 10.5, y: 10.2), startRadius: 0, endRadius: 8.5))
    ctx.stroke(body, with: .color(Color(0xB45309)), lineWidth: 0.6)
    var eyes = ctx
    eyes.translateBy(x: 0, y: 12.2); eyes.scaleBy(x: 1, y: p.eyes); eyes.translateBy(x: 0, y: -12.2)
    eyes.fill(ellipse(9.9, 12.2, 0.95, 1.25), with: .color(Color(0x3B2F2F)))
    eyes.fill(ellipse(14.1, 12.2, 0.95, 1.25), with: .color(Color(0x3B2F2F)))
    eyes.fill(circle(10.2, 11.7, 0.35), with: .color(.white))
    eyes.fill(circle(14.4, 11.7, 0.35), with: .color(.white))
    ctx.fill(circle(8.3, 14.2, 0.9), with: .color(Color(0xF87171, 0.55)))
    ctx.fill(circle(15.7, 14.2, 0.9), with: .color(Color(0xF87171, 0.55)))
    ctx.stroke(Path { $0.move(to: CGPoint(x: 10.8, y: 14.6)); $0.addQuadCurve(to: CGPoint(x: 13.2, y: 14.6), control: CGPoint(x: 12, y: 15.8)) }, with: .color(Color(0x3B2F2F)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
}

// 2. Extraer: libélula cuentagotas
func drawDragonfly(_ c: GraphicsContext, _ p: Pose) {
    var ctx = c
    withPose(&ctx, origin: CGPoint(x: 12, y: 12), p)
    var w = ctx
    w.opacity = p.wingAlpha / 0.7
    for (cx, cy, rx, ry, rot, fill, stroke) in [(6.9, 8.4, 4.9, 1.9, -22.0, Color(0x5EEAD4, 0.45), Color(0x0D9488)), (17.1, 8.4, 4.9, 1.9, 22.0, Color(0x5EEAD4, 0.45), Color(0x0D9488)),
                                                (7.4, 11.8, 3.9, 1.5, -8.0, Color(0xFDE047, 0.4), Color(0xD97706)), (16.6, 11.8, 3.9, 1.5, 8.0, Color(0xFDE047, 0.4), Color(0xD97706))] {
        var wing = w
        wing.translateBy(x: cx, y: cy); wing.scaleBy(x: 1, y: p.wings); wing.translateBy(x: -cx, y: -cy)
        let e = ellipse(cx, cy, rx, ry, rot: rot)
        wing.fill(e, with: .color(fill)); wing.stroke(e, with: .color(stroke), lineWidth: 0.55)
    }
    let tube = Path { q in q.move(to: CGPoint(x: 11.0, y: 12)); q.addLine(to: CGPoint(x: 13.0, y: 12)); q.addLine(to: CGPoint(x: 12.4, y: 19.8)); q.addQuadCurve(to: CGPoint(x: 11.6, y: 19.8), control: CGPoint(x: 12, y: 21.2)); q.closeSubpath() }
    ctx.fill(tube, with: .color(Color(0xFFF7E6)))
    let liquid = Path { q in q.move(to: CGPoint(x: 11.3, y: 15.4)); q.addLine(to: CGPoint(x: 12.7, y: 15.4)); q.addLine(to: CGPoint(x: 12.3, y: 19.6)); q.addQuadCurve(to: CGPoint(x: 11.7, y: 19.6), control: CGPoint(x: 12, y: 20.6)); q.closeSubpath() }
    ctx.fill(liquid, with: .color(Color(0xFD933F, 0.9)))
    ctx.stroke(tube, with: .color(Color(0x954A00)), lineWidth: 0.7)
    let thorax = ellipse(12, 9.6, 2.1, 2.6)
    ctx.fill(thorax, with: .color(Color(0xFD933F))); ctx.stroke(thorax, with: .color(Color(0x954A00)), lineWidth: 0.8)
    ctx.fill(circle(11.4, 8.9, 0.8), with: .color(Color(0xFEF08A)))
    let head = circle(12, 5.3, 1.9)
    ctx.fill(head, with: .color(Color(0x5EEAD4))); ctx.stroke(head, with: .color(Color(0x0D9488)), lineWidth: 0.7)
    ctx.fill(circle(11.4, 4.7, 0.5), with: .color(.white))
}

// 3. Rejilla: gota de rocío sobre piedra con hojas
func drawDew(_ c: GraphicsContext, _ p: Pose) {
    var base = c
    base.fill(ellipse(7.0, 19.6, 2.3, 1.0, rot: -25), with: .color(Color(0x81B29A)))
    base.stroke(ellipse(7.0, 19.6, 2.3, 1.0, rot: -25), with: .color(Color(0x2D5A3C)), lineWidth: 0.5)
    base.fill(ellipse(17.0, 19.6, 2.3, 1.0, rot: 25), with: .color(Color(0x81B29A)))
    base.stroke(ellipse(17.0, 19.6, 2.3, 1.0, rot: 25), with: .color(Color(0x2D5A3C)), lineWidth: 0.5)
    let pebble = ellipse(12, 20.4, 5.4, 2.2)
    base.fill(pebble, with: .color(Color(0xC1C9BF))); base.stroke(pebble, with: .color(Color(0x717971)), lineWidth: 0.5)
    var ctx = c
    withPose(&ctx, origin: CGPoint(x: 12, y: 18.6), p)
    let drop = Path { q in
        q.move(to: CGPoint(x: 12, y: 3.4))
        q.addCurve(to: CGPoint(x: 6.8, y: 13.2), control1: CGPoint(x: 12, y: 3.4), control2: CGPoint(x: 6.8, y: 9.6))
        q.addCurve(to: CGPoint(x: 12, y: 18.6), control1: CGPoint(x: 6.8, y: 16.2), control2: CGPoint(x: 9.1, y: 18.6))
        q.addCurve(to: CGPoint(x: 17.2, y: 13.2), control1: CGPoint(x: 14.9, y: 18.6), control2: CGPoint(x: 17.2, y: 16.2))
        q.addCurve(to: CGPoint(x: 12, y: 3.4), control1: CGPoint(x: 17.2, y: 9.6), control2: CGPoint(x: 12, y: 3.4))
        q.closeSubpath()
    }
    ctx.fill(drop, with: .linearGradient(Gradient(colors: [Color(0xE3F6EE), Color(0xBDECDC), Color(0x7CA99A)]), startPoint: CGPoint(x: 12, y: 4), endPoint: CGPoint(x: 12, y: 18.6)))
    ctx.stroke(drop, with: .color(Color(0x2D594C)), lineWidth: 0.8)
    ctx.fill(ellipse(9.9, 11.0, 0.8, 1.8, rot: 20), with: .color(.white.opacity(0.8)))
    var eyes = ctx
    eyes.translateBy(x: 0, y: 13.8); eyes.scaleBy(x: 1, y: p.eyes); eyes.translateBy(x: 0, y: -13.8)
    eyes.fill(circle(10.4, 13.8, 0.75), with: .color(Color(0x144136)))
    eyes.fill(circle(13.6, 13.8, 0.75), with: .color(Color(0x144136)))
    ctx.fill(circle(9.2, 15.1, 0.7), with: .color(Color(0xF4A261, 0.5)))
    ctx.fill(circle(14.8, 15.1, 0.7), with: .color(Color(0xF4A261, 0.5)))
    ctx.stroke(Path { $0.move(to: CGPoint(x: 11.2, y: 15.4)); $0.addQuadCurve(to: CGPoint(x: 12.8, y: 15.4), control: CGPoint(x: 12, y: 16.2)) }, with: .color(Color(0x144136)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
}

// 4. Jardín: brote en maceta
func drawSprout(_ c: GraphicsContext, _ p: Pose) {
    var ctx = c
    let pot = Path { q in q.move(to: CGPoint(x: 7.4, y: 14.8)); q.addLine(to: CGPoint(x: 16.6, y: 14.8)); q.addLine(to: CGPoint(x: 15.5, y: 20.6)); q.addQuadCurve(to: CGPoint(x: 14.4, y: 21.6), control: CGPoint(x: 15.3, y: 21.6)); q.addLine(to: CGPoint(x: 9.6, y: 21.6)); q.addQuadCurve(to: CGPoint(x: 8.5, y: 20.6), control: CGPoint(x: 8.7, y: 21.6)); q.closeSubpath() }
    var stem = ctx
    withPose(&stem, origin: CGPoint(x: 12, y: 14), p)
    stem.stroke(Path { $0.move(to: CGPoint(x: 12, y: 13.6)); $0.addCurve(to: CGPoint(x: 12, y: 7.4), control1: CGPoint(x: 12, y: 11.4), control2: CGPoint(x: 11.5, y: 9.4)) }, with: .color(Color(0x2D5A3C)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    let left = Path { q in q.move(to: CGPoint(x: 12, y: 10.6)); q.addCurve(to: CGPoint(x: 7.0, y: 11.2), control1: CGPoint(x: 9.8, y: 8.4), control2: CGPoint(x: 6.2, y: 8.9)); q.addCurve(to: CGPoint(x: 12, y: 10.6), control1: CGPoint(x: 8.1, y: 12.7), control2: CGPoint(x: 10.8, y: 12.0)); q.closeSubpath() }
    let right = Path { q in q.move(to: CGPoint(x: 12, y: 8.8)); q.addCurve(to: CGPoint(x: 17.0, y: 9.6), control1: CGPoint(x: 14.4, y: 6.6), control2: CGPoint(x: 17.9, y: 7.3)); q.addCurve(to: CGPoint(x: 12, y: 8.8), control1: CGPoint(x: 16.0, y: 11.1), control2: CGPoint(x: 13.2, y: 10.4)); q.closeSubpath() }
    stem.fill(left, with: .color(Color(0x81B29A))); stem.stroke(left, with: .color(Color(0x144226)), lineWidth: 0.55)
    stem.fill(right, with: .color(Color(0xA1D2AC))); stem.stroke(right, with: .color(Color(0x144226)), lineWidth: 0.55)
    stem.fill(circle(12, 6.7, 1.1), with: .color(Color(0xFBBF24))); stem.stroke(circle(12, 6.7, 1.1), with: .color(Color(0xB45309)), lineWidth: 0.4)
    ctx.fill(pot, with: .color(Color(0xC8644A))); ctx.stroke(pot, with: .color(Color(0x713700)), lineWidth: 0.6)
    let rim = Path(roundedRect: CGRect(x: 6.5, y: 13.3, width: 11, height: 2.2), cornerRadius: 1.1)
    ctx.fill(rim, with: .color(Color(0xE07A5F))); ctx.stroke(rim, with: .color(Color(0x713700)), lineWidth: 0.6)
    for x in [10.5, 13.5] {
        ctx.stroke(Path { $0.move(to: CGPoint(x: x - 0.65, y: 17.6)); $0.addQuadCurve(to: CGPoint(x: x + 0.65, y: 17.6), control: CGPoint(x: x, y: 16.9)) }, with: .color(Color(0xFFF7E6)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
    }
    ctx.stroke(Path { $0.move(to: CGPoint(x: 11.3, y: 19.0)); $0.addQuadCurve(to: CGPoint(x: 12.7, y: 19.0), control: CGPoint(x: 12, y: 19.7)) }, with: .color(Color(0xFFF7E6)), style: StrokeStyle(lineWidth: 0.55, lineCap: .round))
}

// Logotipo: ventana en arco con sol de hojas, haz prismático y gota
func drawLogo(_ ctx: GraphicsContext) {
    var c = ctx
    let arch = Path { q in q.move(to: CGPoint(x: 3, y: 29)); q.addLine(to: CGPoint(x: 3, y: 14)); q.addArc(center: CGPoint(x: 14, y: 14), radius: 11, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false); q.addLine(to: CGPoint(x: 25, y: 29)); q.addQuadCurve(to: CGPoint(x: 23, y: 31), control: CGPoint(x: 25, y: 31)); q.addLine(to: CGPoint(x: 5, y: 31)); q.addQuadCurve(to: CGPoint(x: 3, y: 29), control: CGPoint(x: 3, y: 31)); q.closeSubpath() }
    c.fill(arch, with: .color(Color(0xFFF8EC)))
    var inner = c
    inner.clip(to: arch)
    for (i, col) in [Color(0xE07A5F), Color(0xF2CC8F), Color(0x81B29A), Color(0x7CA99A)].enumerated() {
        let o = CGFloat(i) * 1.3
        inner.fill(Path { q in q.move(to: CGPoint(x: 15.5, y: 17)); q.addLine(to: CGPoint(x: 27 + o, y: 25 - o * 0.2)); q.addLine(to: CGPoint(x: 27 + o, y: 26.4 - o * 0.2)); q.addLine(to: CGPoint(x: 15.5, y: 17.6)); q.closeSubpath() }.applying(CGAffineTransform(translationX: -o * 1.1, y: o * 1.35)), with: .color(col.opacity(0.9)))
    }
    for k in 0..<12 {
        let a = Double(k) * 30
        let x = 14 + 7.0 * cos(a * .pi / 180), y = 15 + 7.0 * sin(a * .pi / 180)
        inner.fill(ellipse(x, y, 1.0, 2.5, rot: a + 90), with: .color(k % 2 == 0 ? Color(0x2D5A3C) : Color(0x588157)))
    }
    let sun = circle(14, 15, 4.3)
    inner.fill(sun, with: .radialGradient(Gradient(colors: [Color(0xF2CC8F), Color(0xD4A347), Color(0x954A00)]), center: CGPoint(x: 13, y: 14), startRadius: 0, endRadius: 5))
    let drop = Path { q in q.move(to: CGPoint(x: 14, y: 23.2)); q.addQuadCurve(to: CGPoint(x: 12.4, y: 26.6), control: CGPoint(x: 12.4, y: 25)); q.addQuadCurve(to: CGPoint(x: 15.6, y: 26.6), control: CGPoint(x: 14, y: 28.4)); q.addQuadCurve(to: CGPoint(x: 14, y: 23.2), control: CGPoint(x: 15.6, y: 25)); q.closeSubpath() }
    inner.fill(drop, with: .color(Color(0xD97724)))
    c.stroke(arch, with: .color(Color(0xC29B38, 0.85)), lineWidth: 1.2)
}

// Sol espíritu de cabecera
func drawSunSpirit(_ ctx: GraphicsContext, rot: Double) {
    var c = ctx
    c.translateBy(x: 16, y: 16); c.rotate(by: .degrees(rot)); c.translateBy(x: -16, y: -16)
    for k in 0..<8 {
        let a = Double(k) * 45 - 90
        let long: CGFloat = k % 2 == 0 ? 14 : 12.2
        let tip = CGPoint(x: 16 + long * cos(a * .pi / 180), y: 16 + long * sin(a * .pi / 180))
        let b1 = CGPoint(x: 16 + 9 * cos((a - 9) * .pi / 180), y: 16 + 9 * sin((a - 9) * .pi / 180))
        let b2 = CGPoint(x: 16 + 9 * cos((a + 9) * .pi / 180), y: 16 + 9 * sin((a + 9) * .pi / 180))
        c.fill(Path { q in q.move(to: b1); q.addLine(to: tip); q.addLine(to: b2); q.closeSubpath() }, with: .color(k % 2 == 0 ? Color(0xF59E0B) : Color(0xFBBF24)))
    }
    var face = ctx
    face.fill(circle(16, 16, 7), with: .color(Color(0xF59E0B)))
    face.fill(circle(16, 16, 5.5), with: .color(Color(0xFDE047)))
    face.fill(ellipse(14, 15, 0.8, 1.0), with: .color(Color(0x713700)))
    face.fill(ellipse(18, 15, 0.8, 1.0), with: .color(Color(0x713700)))
    face.fill(circle(13, 16.6, 0.8), with: .color(Color(0xF87171, 0.6)))
    face.fill(circle(19, 16.6, 0.8), with: .color(Color(0xF87171, 0.6)))
    face.stroke(Path { $0.move(to: CGPoint(x: 14.5, y: 17.5)); $0.addQuadCurve(to: CGPoint(x: 17.5, y: 17.5), control: CGPoint(x: 16, y: 18.9)) }, with: .color(Color(0x713700)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
}

struct Sheet: View {
    let poses: [(String, Pose)]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(poses.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 26) {
                    Text(item.0).font(.system(size: 13, weight: .semibold)).frame(width: 150, alignment: .leading)
                    Canvas { ctx, size in ctx.scaleBy(x: size.width / 24, y: size.height / 24); drawSeed(ctx, item.1) }.frame(width: 96, height: 96)
                    Canvas { ctx, size in ctx.scaleBy(x: size.width / 24, y: size.height / 24); drawDragonfly(ctx, item.1) }.frame(width: 96, height: 96)
                    Canvas { ctx, size in ctx.scaleBy(x: size.width / 24, y: size.height / 24); drawDew(ctx, item.1) }.frame(width: 96, height: 96)
                    Canvas { ctx, size in ctx.scaleBy(x: size.width / 24, y: size.height / 24); drawSprout(ctx, item.1) }.frame(width: 96, height: 96)
                }
            }
            HStack(spacing: 26) {
                Text("A tamaño real (24 pt)").font(.system(size: 13, weight: .semibold)).frame(width: 150, alignment: .leading)
                Canvas { ctx, size in drawSeed(ctx, Pose()) }.frame(width: 24, height: 24)
                Canvas { ctx, size in drawDragonfly(ctx, Pose()) }.frame(width: 24, height: 24)
                Canvas { ctx, size in drawDew(ctx, Pose()) }.frame(width: 24, height: 24)
                Canvas { ctx, size in drawSprout(ctx, Pose()) }.frame(width: 24, height: 24)
                Canvas { ctx, size in ctx.scaleBy(x: size.width / 28, y: size.height / 32); drawLogo(ctx) }.frame(width: 28, height: 32)
                Canvas { ctx, size in drawSunSpirit(ctx, rot: 0) }.frame(width: 32, height: 32)
            }
            HStack(spacing: 26) {
                Text("Logo y sol (x4)").font(.system(size: 13, weight: .semibold)).frame(width: 150, alignment: .leading)
                Canvas { ctx, size in ctx.scaleBy(x: size.width / 28, y: size.height / 32); drawLogo(ctx) }.frame(width: 112, height: 128)
                Canvas { ctx, size in ctx.scaleBy(x: size.width / 32, y: size.height / 32); drawSunSpirit(ctx, rot: 0) }.frame(width: 128, height: 128)
                Canvas { ctx, size in ctx.scaleBy(x: size.width / 32, y: size.height / 32); drawSunSpirit(ctx, rot: 90) }.frame(width: 128, height: 128)
            }
        }
        .padding(24)
        .background(Color(0xFCF9F1))
    }
}

@MainActor func run() {
    let sheet = Sheet(poses: [
        ("Reposo", Pose()),
        ("Pico (30-50 %)", Pose(rot: -6, dy: -4, sx: 0.96, sy: 1.06, eyes: 1, wings: 0.55, wingAlpha: 0.3)),
        ("Parpadeo / 75 %", Pose(rot: 6, dy: 0.5, sx: 1.03, sy: 0.97, eyes: 0.1, wings: 0.8, wingAlpha: 0.5)),
    ])
    let r = ImageRenderer(content: sheet)
    r.scale = 2
    guard let img = r.cgImage else { print("sin imagen"); return }
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "creatures.png"))
    print("ok \(img.width)x\(img.height)")
}
@main struct Main { @MainActor static func main() { run() } }
