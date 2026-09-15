// Operaciones de máscara sin color (recuento, bbox, unión, mapa de instancias,
// polígonos convexos). Nada de lógica de color: eso vive en el motor C.
import CoreGraphics

/// Utilidades de máscaras width * height (0...255, sin stride).
public enum MaskOps {
    /// Umbral de "dentro" para cobertura, bbox y asociaciones.
    public static let insideThreshold: UInt8 = 128

    /// Cobertura (fracción >= 128) y bbox de los píxeles >= 128.
    public static func stats(_ mask: [UInt8], width: Int, height: Int) -> (count: Int, coverage: Double, bbox: CGRect) {
        guard width >= 1, height >= 1, mask.count >= width * height else { return (0, 0, .zero) }
        var count = 0
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        mask.withUnsafeBufferPointer { m in
            for y in 0..<height {
                let row = y * width
                for x in 0..<width where m[row + x] >= insideThreshold {
                    count += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard count > 0 else { return (0, 0, .zero) }
        let bbox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return (count, Double(count) / Double(width * height), bbox)
    }

    /// Fracción de píxeles >= 128.
    public static func coverage(_ mask: [UInt8], width: Int, height: Int) -> Double {
        stats(mask, width: width, height: height).coverage
    }

    /// Píxeles > 0 (la cuenta que devuelven las funciones de máscara del motor).
    public static func nonZero(_ mask: [UInt8]) -> Int {
        mask.withUnsafeBufferPointer { m in
            var n = 0
            for i in 0..<m.count where m[i] != 0 { n += 1 }
            return n
        }
    }

    /// Máscara binaria: 255 donde `mask` >= 128 (`insideThreshold`), 0 en el resto.
    /// La instancia de Vision es blanda; la cadena y el motor solo ven esta versión.
    public static func binarize(_ mask: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: mask.count)
        mask.withUnsafeBufferPointer { m in
            out.withUnsafeMutableBufferPointer { o in
                for i in 0..<m.count where m[i] >= insideThreshold { o[i] = 255 }
            }
        }
        return out
    }

    /// Máximo por píxel; nil si no hay máscaras.
    public static func union(_ masks: [[UInt8]]) -> [UInt8]? {
        guard var out = masks.first else { return nil }
        for m in masks.dropFirst() {
            let n = min(out.count, m.count)
            m.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    for i in 0..<n where src[i] > dst[i] { dst[i] = src[i] }
                }
            }
        }
        return out
    }

    /// 255 donde `before` > 0 y `after` == 0.
    public static func removed(before: [UInt8], after: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: before.count)
        let n = min(before.count, after.count)
        before.withUnsafeBufferPointer { b in
            after.withUnsafeBufferPointer { a in
                out.withUnsafeMutableBufferPointer { o in
                    for i in 0..<n where b[i] != 0 && a[i] == 0 { o[i] = 255 }
                }
            }
        }
        return out
    }

    /// Mapa de instancias: en cada píxel, el id (acotado a 1...255) de la persona
    /// con mayor valor >= 128; 0 = fondo. `people` en orden de prioridad de desempate.
    public static func instanceOverlay(_ people: [PersonInstance], width: Int, height: Int) -> [UInt8] {
        let count = width * height
        var out = [UInt8](repeating: 0, count: count)
        var best = [UInt8](repeating: 0, count: count)
        for p in people where p.mask.count >= count {
            let label = UInt8(clamping: max(1, p.id))
            p.mask.withUnsafeBufferPointer { m in
                best.withUnsafeMutableBufferPointer { bb in
                    out.withUnsafeMutableBufferPointer { ob in
                        for i in 0..<count where m[i] >= insideThreshold && m[i] > bb[i] {
                            bb[i] = m[i]
                            ob[i] = label
                        }
                    }
                }
            }
        }
        return out
    }

    /// Valor de la máscara en el píxel que contiene (x, y); 0 fuera del raster.
    public static func value(_ mask: [UInt8], width: Int, height: Int, x: Double, y: Double) -> UInt8 {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0 else { return 0 }
        let ix = Int(x.rounded(.down)), iy = Int(y.rounded(.down))
        guard ix < width, iy < height, mask.count >= width * height else { return 0 }
        return mask[iy * width + ix]
    }

    /// Rasteriza polígonos convexos (evaluados en el centro de cada píxel, sin
    /// antialiasing): 255 dentro de alguno, 0 fuera. `clip` opcional: además
    /// exige clip >= 128.
    public static func fillConvexPolygons(_ polygons: [[CGPoint]], width: Int, height: Int,
                                          clip: [UInt8]? = nil, clipErosion: Int = 0) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        for poly in polygons where poly.count >= 3 {
            let xs = poly.map(\.x), ys = poly.map(\.y)
            guard let minXf = xs.min(), let maxXf = xs.max(), let minYf = ys.min(), let maxYf = ys.max(),
                  minXf.isFinite, maxXf.isFinite, minYf.isFinite, maxYf.isFinite else { continue }
            let x0 = max(0, Int((minXf - 0.5).rounded(.down)))
            let x1 = min(width - 1, Int((maxXf - 0.5).rounded(.up)))
            let y0 = max(0, Int((minYf - 0.5).rounded(.down)))
            let y1 = min(height - 1, Int((maxYf - 0.5).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let i = y * width + x
                    if out[i] != 0 { continue }
                    if let clip, !insideEroded(clip, width: width, height: height, x: x, y: y, radius: clipErosion) {
                        continue
                    }
                    if pointInConvexPolygon(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), poly) {
                        out[i] = 255
                    }
                }
            }
        }
        return out
    }

    /// true si todos los píxeles del cuadrado de lado 2·radius + 1 centrado en (x, y)
    /// están dentro del raster con máscara >= 128 (erosión binaria puntual).
    public static func insideEroded(_ mask: [UInt8], width: Int, height: Int, x: Int, y: Int, radius: Int) -> Bool {
        guard mask.count >= width * height else { return false }
        let r = max(0, radius)
        guard x - r >= 0, y - r >= 0, x + r < width, y + r < height else { return false }
        for yy in (y - r)...(y + r) {
            for xx in (x - r)...(x + r) where mask[yy * width + xx] < insideThreshold {
                return false
            }
        }
        return true
    }

    /// true si `p` está dentro o sobre el borde de un polígono convexo (cualquier orientación).
    public static func pointInConvexPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var sign = 0
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross > 0 {
                if sign < 0 { return false }
                sign = 1
            } else if cross < 0 {
                if sign > 0 { return false }
                sign = -1
            }
        }
        return true
    }

    /// Envolvente convexa (monotone chain), sin puntos colineales; orden antihorario
    /// en ejes matemáticos.
    public static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let pts = points.filter { $0.x.isFinite && $0.y.isFinite }
            .sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard pts.count >= 3 else { return pts }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for p in pts {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in pts.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Intersección de dos polígonos convexos (Sutherland–Hodgman con `clipper`
    /// convexo). Devuelve [] si no se solapan.
    public static func intersectConvex(_ subject: [CGPoint], _ clipper: [CGPoint]) -> [CGPoint] {
        guard subject.count >= 3, clipper.count >= 3 else { return [] }
        // Orientación del recortador.
        var area: CGFloat = 0
        for i in 0..<clipper.count {
            let a = clipper[i], b = clipper[(i + 1) % clipper.count]
            area += a.x * b.y - b.x * a.y
        }
        let orient: CGFloat = area >= 0 ? 1 : -1
        var output = subject
        for i in 0..<clipper.count {
            guard !output.isEmpty else { break }
            let a = clipper[i], b = clipper[(i + 1) % clipper.count]
            func inside(_ p: CGPoint) -> Bool {
                orient * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) >= 0
            }
            func intersection(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
                let d1 = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                let d2 = (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x)
                let t = d1 / (d1 - d2)
                return CGPoint(x: p.x + t * (q.x - p.x), y: p.y + t * (q.y - p.y))
            }
            let input = output
            output = []
            for j in 0..<input.count {
                let cur = input[j], prev = input[(j + input.count - 1) % input.count]
                if inside(cur) {
                    if !inside(prev) { output.append(intersection(prev, cur)) }
                    output.append(cur)
                } else if inside(prev) {
                    output.append(intersection(prev, cur))
                }
            }
        }
        return output.count >= 3 ? output : []
    }
}
