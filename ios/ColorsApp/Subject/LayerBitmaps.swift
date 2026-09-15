// Mapas de bits de las capas (Resultado > "Ver máscara" y el inspector de
// capas): máscaras, personas, piel, peso por píxel y swatch por píxel pintados
// como CGImage RGBA para superponerlos a la foto. Solo representación: los
// valores vienen tal cual de SubjectKit y del motor C (sin lógica de color).
// Funciones puras y sin estado: se llaman fuera del MainActor. Los bucles por
// píxel usan buffers inseguros: la build del usuario es Debug (-Onone) y una
// capa de 1024 px son ~1 M de píxeles.
import Foundation
import CoreGraphics
import ColorEngine
import SubjectKit

enum LayerBitmaps {
    struct RGB: Equatable, Sendable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    /// Colores de las personas (índice en `people`, ordenadas por cobertura).
    static let personColors: [RGB] = [
        RGB(r: 255, g: 99, b: 71), RGB(r: 65, g: 105, b: 225), RGB(r: 46, g: 204, b: 113),
        RGB(r: 255, g: 204, b: 0), RGB(r: 186, g: 85, b: 211), RGB(r: 0, g: 206, b: 209),
    ]

    static func personColor(_ index: Int) -> RGB {
        personColors[((index % personColors.count) + personColors.count) % personColors.count]
    }

    static let magenta = RGB(r: 255, g: 0, b: 255)
    static let faceOutline = RGB(r: 255, g: 230, b: 0)
    static let regionTint = RGB(r: 0, g: 200, b: 255)

    // MARK: CGImage

    /// CGImage sRGB RGBA (alpha premultiplicada) de `width * height * 4` bytes.
    static func rgbaImage(width: Int, height: Int, premultiplied pixels: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, pixels.count == width * height * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// CGImage sRGB opaca de `width * height * 3` bytes RGB.
    static func rgbImage(width: Int, height: Int, rgb: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, rgb.count == width * height * 3 else { return nil }
        return PPMImage(width: width, height: height, rgb: rgb).makeCGImage()
    }

    /// CGImage en gris de 8 bits (máscaras).
    static func grayImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, bytes.count == width * height,
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Reescala una máscara `width` x `height` a `toWidth` x `toHeight` con
    /// CoreGraphics (interpolación alta, como MaskRaster de SubjectKit).
    static func resample(mask: [UInt8], width: Int, height: Int, toWidth: Int, toHeight: Int) throws -> [UInt8] {
        if width == toWidth && height == toHeight { return mask }
        guard let image = grayImage(width: width, height: height, bytes: mask) else {
            throw SubjectError.graphicsUnavailable
        }
        return try MaskRaster.rasterizeMask(image, width: toWidth, height: toHeight)
    }

    // MARK: Capas

    /// Oscurece lo que queda fuera de la máscara (alpha = (255 − m) · 0,78) y
    /// deja ver la foto donde la máscara pesa.
    static func dimOutside(mask: [UInt8], width: Int, height: Int) -> CGImage? {
        guard mask.count == width * height else { return nil }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        var lut = [UInt8](repeating: 0, count: 256)
        for v in 0..<256 { lut[v] = UInt8((Double(255 - v) * 0.78).rounded()) }
        px.withUnsafeMutableBufferPointer { p in
            mask.withUnsafeBufferPointer { m in
                for i in 0..<m.count { p[i * 4 + 3] = lut[Int(m[i])] }
            }
        }
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Tiñe los píxeles de la máscara (alpha proporcional al valor, máximo `alpha`).
    static func tint(mask: [UInt8], width: Int, height: Int, color: RGB, alpha: UInt8) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        guard mask.count == width * height else { return px }
        px.withUnsafeMutableBufferPointer { p in
            mask.withUnsafeBufferPointer { m in
                for i in 0..<m.count where m[i] > 0 {
                    let a = Int(m[i]) * Int(alpha) / 255
                    p[i * 4] = UInt8(Int(color.r) * a / 255)
                    p[i * 4 + 1] = UInt8(Int(color.g) * a / 255)
                    p[i * 4 + 2] = UInt8(Int(color.b) * a / 255)
                    p[i * 4 + 3] = UInt8(a)
                }
            }
        }
        return px
    }

    /// Pinta encima (operador "source over") un color opaco en los píxeles `true`.
    static func paint(_ px: inout [UInt8], where flags: [Bool], color: RGB) {
        guard px.count >= flags.count * 4 else { return }
        px.withUnsafeMutableBufferPointer { p in
            flags.withUnsafeBufferPointer { f in
                for i in 0..<f.count where f[i] {
                    p[i * 4] = color.r
                    p[i * 4 + 1] = color.g
                    p[i * 4 + 2] = color.b
                    p[i * 4 + 3] = 255
                }
            }
        }
    }

    /// Contorno de una máscara (>= 128) con grosor `thickness` px hacia dentro:
    /// píxeles dentro con algún píxel fuera (o el borde de la imagen) en su
    /// cuadrado de lado 2·thickness + 1. Dilatación separable con sumas
    /// acumuladas: O(width · height) sea cual sea el grosor.
    static func outline(mask: [UInt8], width: Int, height: Int, thickness: Int) -> [Bool] {
        let n = width * height
        guard mask.count == n, n > 0 else { return [Bool](repeating: false, count: max(0, n)) }
        let t = max(1, thickness)
        var nearH = [Bool](repeating: false, count: n)
        var edge = [Bool](repeating: false, count: n)
        var prefix = [Int](repeating: 0, count: max(width, height) + 1)
        mask.withUnsafeBufferPointer { m in
            nearH.withUnsafeMutableBufferPointer { near in
                prefix.withUnsafeMutableBufferPointer { pre in
                    for y in 0..<height {
                        let row = y * width
                        for x in 0..<width {
                            pre[x + 1] = pre[x] + (m[row + x] < 128 ? 1 : 0)
                        }
                        for x in 0..<width {
                            near[row + x] = x - t < 0 || x + t >= width || pre[x + t + 1] - pre[x - t] > 0
                        }
                    }
                    edge.withUnsafeMutableBufferPointer { e in
                        for x in 0..<width {
                            for y in 0..<height {
                                pre[y + 1] = pre[y] + (near[y * width + x] ? 1 : 0)
                            }
                            for y in 0..<height where m[y * width + x] >= 128 {
                                e[y * width + x] = y - t < 0 || y + t >= height || pre[y + t + 1] - pre[y - t] > 0
                            }
                        }
                    }
                }
            }
        }
        return edge
    }

    /// Grosor de línea razonable para ver un contorno en pantalla (~1/250 del lado mayor).
    static func lineWidth(width: Int, height: Int) -> Int {
        max(1, max(width, height) / 250)
    }

    /// Cada persona de su color (`allPeopleOverlay` = id de instancia por píxel);
    /// la persona elegida (`highlightIds`) casi opaca y el resto translúcidas.
    static func people(overlay ids: [UInt8], width: Int, height: Int, people: [PersonInstance],
                       highlightIds: Set<Int>) -> CGImage? {
        guard ids.count == width * height else { return nil }
        var colorById: [Int: (RGB, UInt8)] = [:]
        for (i, p) in people.enumerated() {
            let strong = highlightIds.isEmpty || highlightIds.contains(p.id)
            colorById[p.id] = (personColor(i), strong ? 200 : 90)
        }
        // Tabla id -> RGBA premultiplicado (ids 0...255).
        var table = [UInt8](repeating: 0, count: 256 * 4)
        for (id, (c, a)) in colorById where id >= 1 && id < 256 {
            table[id * 4] = UInt8(Int(c.r) * Int(a) / 255)
            table[id * 4 + 1] = UInt8(Int(c.g) * Int(a) / 255)
            table[id * 4 + 2] = UInt8(Int(c.b) * Int(a) / 255)
            table[id * 4 + 3] = a
        }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        px.withUnsafeMutableBufferPointer { p in
            ids.withUnsafeBufferPointer { src in
                table.withUnsafeBufferPointer { tb in
                    for i in 0..<src.count where src[i] != 0 {
                        let k = Int(src[i]) * 4
                        p[i * 4] = tb[k]
                        p[i * 4 + 1] = tb[k + 1]
                        p[i * 4 + 2] = tb[k + 2]
                        p[i * 4 + 3] = tb[k + 3]
                    }
                }
            }
        }
        // Contorno opaco de las personas resaltadas.
        let t = lineWidth(width: width, height: height)
        for (i, p) in people.enumerated() where highlightIds.contains(p.id) {
            paint(&px, where: outline(mask: p.mask, width: width, height: height, thickness: t), color: personColor(i))
        }
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Región de ropa sombreada (cian) sobre la foto.
    static func region(mask: [UInt8], width: Int, height: Int) -> CGImage? {
        var px = tint(mask: mask, width: width, height: height, color: regionTint, alpha: 120)
        paint(&px, where: outline(mask: mask, width: width, height: height, thickness: lineWidth(width: width, height: height)),
              color: regionTint)
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Piel quitada en magenta y la zona de muestra de la cara con contorno amarillo.
    static func skin(removed: [UInt8]?, faceSample: [UInt8]?, width: Int, height: Int) -> CGImage? {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        if let faceSample, faceSample.count == width * height {
            px = tint(mask: faceSample, width: width, height: height, color: faceOutline, alpha: 70)
            paint(&px, where: outline(mask: faceSample, width: width, height: height,
                                      thickness: lineWidth(width: width, height: height)), color: faceOutline)
        }
        if let removed, removed.count == width * height {
            paint(&px, where: removed.map { $0 >= 128 }, color: magenta)
        }
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Mapa de calor del peso por píxel (0...255 del motor): 0 en negro
    /// translúcido (no cuenta) y de morado a amarillo claro según el peso.
    static func heatmap(weights: [UInt8], width: Int, height: Int) -> CGImage? {
        guard weights.count == width * height else { return nil }
        let stops: [(Double, RGB)] = [
            (0.0, RGB(r: 40, g: 11, b: 84)), (0.25, RGB(r: 120, g: 28, b: 109)), (0.5, RGB(r: 206, g: 68, b: 70)),
            (0.75, RGB(r: 249, g: 142, b: 9)), (1.0, RGB(r: 252, g: 255, b: 164)),
        ]
        var lut = [UInt8](repeating: 0, count: 256 * 4)
        lut[3] = 200
        for v in 1..<256 {
            let t = Double(v) / 255
            var k = 0
            while k < stops.count - 2 && t > stops[k + 1].0 { k += 1 }
            let (t0, c0) = stops[k]
            let (t1, c1) = stops[k + 1]
            let f = max(0, min(1, (t - t0) / (t1 - t0)))
            func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * f).rounded()) }
            lut[v * 4] = mix(c0.r, c1.r)
            lut[v * 4 + 1] = mix(c0.g, c1.g)
            lut[v * 4 + 2] = mix(c0.b, c1.b)
            lut[v * 4 + 3] = 255
        }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        px.withUnsafeMutableBufferPointer { p in
            weights.withUnsafeBufferPointer { w in
                lut.withUnsafeBufferPointer { tb in
                    for i in 0..<w.count {
                        let k = Int(w[i]) * 4
                        p[i * 4] = tb[k]
                        p[i * 4 + 1] = tb[k + 1]
                        p[i * 4 + 2] = tb[k + 2]
                        p[i * 4 + 3] = tb[k + 3]
                    }
                }
            }
        }
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Swatch por píxel pintado con el color de su swatch; descartados en gris
    /// rayado, sin peso en negro translúcido. `isolate`: solo ese swatch en color,
    /// el resto oscurecido.
    static func labels(_ labels: [UInt8], width: Int, height: Int, swatches: [Swatch], isolate: Int? = nil) -> CGImage? {
        guard labels.count == width * height else { return nil }
        // Tabla etiqueta -> RGBA; DISCARDED se raya aparte.
        var table = [UInt8](repeating: 0, count: 256 * 4)
        for v in 0..<256 {
            let o = v * 4
            if let isolate {
                if v == isolate, isolate < swatches.count {
                    let s = swatches[isolate]
                    (table[o], table[o + 1], table[o + 2], table[o + 3]) = (s.r, s.g, s.b, 255)
                } else {
                    table[o + 3] = 190
                }
            } else if UInt8(v) == paletteLabelNone {
                table[o + 3] = 150
            } else if v < swatches.count {
                let s = swatches[v]
                (table[o], table[o + 1], table[o + 2], table[o + 3]) = (s.r, s.g, s.b, 255)
            }
        }
        let striped = isolate == nil
        var px = [UInt8](repeating: 0, count: width * height * 4)
        px.withUnsafeMutableBufferPointer { p in
            labels.withUnsafeBufferPointer { l in
                table.withUnsafeBufferPointer { tb in
                    for y in 0..<height {
                        for x in 0..<width {
                            let i = y * width + x
                            let o = i * 4
                            if striped && l[i] == paletteLabelDiscarded {
                                let v: UInt8 = ((x + y) / 3) % 2 == 0 ? 150 : 100
                                (p[o], p[o + 1], p[o + 2], p[o + 3]) = (v, v, v, 255)
                            } else {
                                let k = Int(l[i]) * 4
                                (p[o], p[o + 1], p[o + 2], p[o + 3]) = (tb[k], tb[k + 1], tb[k + 2], tb[k + 3])
                            }
                        }
                    }
                }
            }
        }
        return rgbaImage(width: width, height: height, premultiplied: px)
    }

    /// Label map a color sin transparencia (diagnóstico `<base>.labels.png`):
    /// como `ce ... --debug-dir` labels.ppm (NONE negro, DISCARDED gris 128).
    static func labelsOpaque(_ labels: [UInt8], width: Int, height: Int, swatches: [Swatch]) -> CGImage? {
        guard labels.count == width * height else { return nil }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let l = labels[i]
            if l == paletteLabelDiscarded {
                (rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]) = (128, 128, 128)
            } else if l != paletteLabelNone, Int(l) < swatches.count {
                let s = swatches[Int(l)]
                (rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]) = (s.r, s.g, s.b)
            }
        }
        return rgbImage(width: width, height: height, rgb: rgb)
    }

    /// Recorte de `image` (en píxeles del raster) alrededor de `bbox` con un
    /// margen del 8 %; nil si el rectángulo queda vacío.
    static func crop(_ image: CGImage, bbox: CGRect, padding: Double = 0.08) -> CGImage? {
        guard !bbox.isEmpty, !bbox.isNull else { return nil }
        let pad = max(bbox.width, bbox.height) * padding
        let rect = bbox.insetBy(dx: -pad, dy: -pad).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty else { return nil }
        return image.cropping(to: rect)
    }
}
