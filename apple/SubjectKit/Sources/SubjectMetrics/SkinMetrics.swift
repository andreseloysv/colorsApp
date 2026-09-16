// Métricas de medida (no de producto) del recorte de SubjectKit: cuánta piel, prenda y fondo
// llega a la paleta. Las usan `visionmask report` y los tests de harness/people; la app no
// enlaza este módulo. Toda la aritmética de color es del motor (srgbToLab, deltaE2000,
// paletteDebugLayers); aquí solo se clasifica y se suma.
//
// Clase de un color: la referencia más cercana en ΔE00 si está a <= `threshold` (10) entre
// prendas anotadas (harness/people/expected.json), parches de piel (iluminados y EN SOMBRA,
// apple/SubjectKit/Fixtures/people_references.json «skin» + «skin_shaded») y parches de fondo;
// si no, «otro». Tres medidas por máscara:
//   - swatches: peso de los swatches de la paleta por clase (lo que medía la versión anterior,
//     ahora con piel en sombra).
//   - paleta por píxel reducido: el motor promedia bloques del raster (ce_image_reduce) y cada
//     píxel reducido alimenta un swatch (labelMap) con un peso (weightMap). Se suma el peso de
//     los píxeles reducidos que alimentan swatches CONSERVADOS según la clase de SU color: la
//     piel en sombra o mezclada en los bordes forma parte de un swatch marrón aunque el swatch
//     entero no se parezca a un parche de piel (verificación de ADR-010, 05 y 07). Es «qué
//     fracción de la paleta viene de píxeles de piel».
//   - máscara por píxel: fracción de los píxeles de la máscara (>= 128) de clase piel.
// Las zonas de pelo («hair_zones»: pelo largo castaño con color de piel en sombra sobre la
// región de ropa) no cuentan como piel en las medidas por píxel.
import CoreGraphics
import ColorEngine

public enum ColorClass: String, CaseIterable, Sendable {
    case garment = "prenda", skin = "piel", background = "fondo", other = "otro"
}

/// Referencias de color de una foto.
public struct ColorReferences: Sendable {
    public var refs: [(cls: ColorClass, lab: Lab)]
    /// Rectángulos [x0, y0, x1) x [y0, y1) en píxeles del raster donde la piel no cuenta (pelo).
    public var hairZones: [[Int]]
    public var threshold: Double

    public init(garments: [String], skin: [String], background: [String], hairZones: [[Int]] = [], threshold: Double = 10) {
        func lab(_ hex: String) -> Lab? {
            var s = hex
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            return srgbToLab(r: UInt8(v >> 16 & 0xff), g: UInt8(v >> 8 & 0xff), b: UInt8(v & 0xff))
        }
        refs = garments.compactMap { lab($0).map { (ColorClass.garment, $0) } }
            + skin.compactMap { lab($0).map { (ColorClass.skin, $0) } }
            + background.compactMap { lab($0).map { (ColorClass.background, $0) } }
        self.hairZones = hairZones.filter { $0.count == 4 }
        self.threshold = threshold
    }

    /// Referencia más cercana a <= threshold (empate: el orden prenda, piel, fondo); si no, otro.
    public func classify(_ lab: Lab) -> ColorClass {
        var best: (ColorClass, Double)? = nil
        for r in refs {
            let d = deltaE2000(lab, r.lab)
            if d <= threshold, best == nil || d < best!.1 { best = (r.cls, d) }
        }
        return best?.0 ?? .other
    }

    func inHair(x: Double, y: Double) -> Bool {
        hairZones.contains { z in x >= Double(z[0]) && x < Double(z[2]) && y >= Double(z[1]) && y < Double(z[3]) }
    }
}

/// Medidas de una máscara.
public struct SkinShare: Sendable {
    /// Píxeles de la máscara (>= 128); 0 sin máscara (foto completa).
    public let maskPixels: Int
    /// Fracción de esos píxeles de clase piel fuera de las zonas de pelo.
    public let maskSkinFraction: Double
    /// Peso de la paleta por clase según el color de cada píxel reducido (piel sin zonas de pelo:
    /// el pelo cuenta en «otro»).
    public let paletteWeight: [ColorClass: Double]
    /// Peso de los swatches por clase.
    public let swatchWeight: [ColorClass: Double]
    public let swatches: [Swatch]
}

public enum SkinMetrics {
    /// Mide `mask` (nil = foto completa) sobre el raster RGBA con las opciones de paleta del motor.
    public static func measure(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int, mask: [UInt8]?,
                               references: ColorReferences,
                               paletteOptions: PaletteOptions = .default) throws -> SkinShare {
        var cache: [UInt32: ColorClass] = [:]
        func cls(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> ColorClass {
            let key = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
            if let c = cache[key] { return c }
            let c = references.classify(srgbToLab(r: r, g: g, b: b))
            cache[key] = c
            return c
        }
        var maskPixels = 0, skinPixels = 0
        if let mask {
            for y in 0..<height {
                for x in 0..<width where mask[y * width + x] >= 128 {
                    maskPixels += 1
                    let o = y * stride + x * 4
                    if cls(rgba[o], rgba[o + 1], rgba[o + 2]) == .skin, !references.inHair(x: Double(x) + 0.5, y: Double(y) + 0.5) {
                        skinPixels += 1
                    }
                }
            }
        }
        let layers: PaletteDebugLayers
        if let mask {
            layers = try mask.withUnsafeBufferPointer { m in
                try paletteDebugLayers(rgba: rgba, width: width, height: height, stride: stride, paletteOptions: paletteOptions,
                                       mask: m)
            }
        } else {
            layers = try paletteDebugLayers(rgba: rgba, width: width, height: height, stride: stride, paletteOptions: paletteOptions)
        }
        let rw = layers.debug.reducedWidth, rh = layers.debug.reducedHeight
        let maxSide = Int(paletteOptions.maxSide)
        let f = max(1, (max(width, height) + maxSide - 1) / maxSide)
        var weights: [ColorClass: Double] = [:]
        var total = 0.0
        for ry in 0..<rh {
            for rx in 0..<rw {
                let i = ry * rw + rx
                guard layers.labelMap[i] < paletteLabelDiscarded else { continue }
                let w = Double(layers.weightMap[i])
                guard w > 0 else { continue }
                var c = cls(layers.reducedRGB[3 * i], layers.reducedRGB[3 * i + 1], layers.reducedRGB[3 * i + 2])
                if c == .skin, references.inHair(x: (Double(rx) + 0.5) * Double(f), y: (Double(ry) + 0.5) * Double(f)) {
                    c = .other
                }
                weights[c, default: 0] += w
                total += w
            }
        }
        var palette: [ColorClass: Double] = [:]
        var swatchWeight: [ColorClass: Double] = [:]
        for c in ColorClass.allCases {
            palette[c] = total > 0 ? (weights[c] ?? 0) / total : 0
            swatchWeight[c] = 0
        }
        for s in layers.analysis.swatches { swatchWeight[references.classify(s.lab), default: 0] += s.weight }
        return SkinShare(maskPixels: maskPixels, maskSkinFraction: maskPixels > 0 ? Double(skinPixels) / Double(maskPixels) : 0,
                         paletteWeight: palette, swatchWeight: swatchWeight, swatches: layers.analysis.swatches)
    }
}
