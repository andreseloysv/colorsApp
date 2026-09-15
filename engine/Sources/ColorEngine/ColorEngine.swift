// Wrapper Swift mínimo sobre el motor C (CColorEngine). Solo tipos y llamadas
// directas: toda la matemática vive en C para que iOS y WASM compartan bits.
import CColorEngine

/// Color en CIELAB (D65). `L` en [0, 100].
public struct Lab: Equatable, Hashable, Sendable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    init(_ c: ce_lab) {
        self.init(L: c.L, a: c.a, b: c.b)
    }

    var cValue: ce_lab {
        ce_lab(L: L, a: a, b: b)
    }
}

/// Versión del motor C.
public var colorEngineVersion: String {
    String(cString: ce_version())
}

/// sRGB de 8 bits -> CIELAB (D65, matriz derivada).
public func srgbToLab(r: UInt8, g: UInt8, b: UInt8) -> Lab {
    Lab(ce_srgb8_to_lab(r, g, b))
}

/// CIELAB -> sRGB de 8 bits (clamp + redondeo).
public func labToSrgb8(_ lab: Lab) -> (r: UInt8, g: UInt8, b: UInt8) {
    var r: UInt8 = 0
    var g: UInt8 = 0
    var b: UInt8 = 0
    ce_lab_to_srgb8(lab.cValue, &r, &g, &b)
    return (r, g, b)
}

/// ΔE00 (CIEDE2000, kL = kC = kH = 1).
public func deltaE2000(_ x: Lab, _ y: Lab) -> Double {
    ce_de2000(x.cValue, y.cValue)
}

/// ΔE00 con factores paramétricos.
public func deltaE2000(_ x: Lab, _ y: Lab, kL: Double, kC: Double, kH: Double) -> Double {
    ce_de2000_k(x.cValue, y.cValue, kL, kC, kH)
}

/// ΔE*ab (CIE 1976).
public func deltaE76(_ x: Lab, _ y: Lab) -> Double {
    ce_de76(x.cValue, y.cValue)
}

// MARK: - Capa 2: extracción de paleta

/// Error del motor C: `code` es el ce_status negativo (ver ce.h).
public enum ColorEngineError: Error, Equatable, Sendable {
    /// El buffer es más corto que (height - 1) * stride + width * 4.
    case bufferTooSmall(required: Int, actual: Int)
    /// ce_palette_extract devolvió un código negativo.
    case engine(code: Int32)
}

/// Swatch de la paleta: Lab (D65), sRGB8 (Lab -> sRGB8 con clamp) y peso
/// relativo; la suma de pesos de una paleta es 1.
public struct Swatch: Equatable, Hashable, Sendable {
    public var lab: Lab
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var weight: Double

    public init(lab: Lab, r: UInt8, g: UInt8, b: UInt8, weight: Double) {
        self.lab = lab
        self.r = r
        self.g = g
        self.b = b
        self.weight = weight
    }

    init(_ c: ce_swatch) {
        self.init(lab: Lab(c.lab), r: c.rgb.0, g: c.rgb.1, b: c.rgb.2, weight: c.weight)
    }

    /// "#rrggbb" en minúsculas (sin Foundation).
    public var hex: String {
        let digits = Array("0123456789abcdef")
        var s = "#"
        for v in [r, g, b] {
            s.append(digits[Int(v >> 4)])
            s.append(digits[Int(v & 0xF)])
        }
        return s
    }
}

/// Opciones de ce_palette_extract (ver ce.h para rangos y semántica).
/// `centerSigma <= 0` = peso uniforme.
public struct PaletteOptions: Equatable, Sendable {
    public var kInit: Int32
    public var maxIters: Int32
    public var maxColors: Int32
    public var maxSide: Int32
    public var centerSigma: Double
    public var mergeDeltaE: Double
    public var minWeight: Double
    public var skinRule: Bool

    /// Valores de ce_palette_opts_default (k 6, 20 iteraciones, 5 colores,
    /// lado 256, sigma 0.35, fusión ΔE00 < 5, descarte < 5 %, sin regla de piel).
    public static var `default`: PaletteOptions {
        var o = ce_palette_opts()
        ce_palette_opts_default(&o)
        return PaletteOptions(o)
    }

    public init(kInit: Int32, maxIters: Int32, maxColors: Int32, maxSide: Int32,
                centerSigma: Double, mergeDeltaE: Double, minWeight: Double, skinRule: Bool) {
        self.kInit = kInit
        self.maxIters = maxIters
        self.maxColors = maxColors
        self.maxSide = maxSide
        self.centerSigma = centerSigma
        self.mergeDeltaE = mergeDeltaE
        self.minWeight = minWeight
        self.skinRule = skinRule
    }

    init(_ o: ce_palette_opts) {
        self.init(kInit: o.k_init, maxIters: o.max_iters, maxColors: o.max_colors, maxSide: o.max_side,
                  centerSigma: o.center_sigma, mergeDeltaE: o.merge_de, minWeight: o.min_weight,
                  skinRule: o.skin_rule != 0)
    }

    var cValue: ce_palette_opts {
        ce_palette_opts(k_init: kInit, max_iters: maxIters, max_colors: maxColors, max_side: maxSide,
                        center_sigma: centerSigma, merge_de: mergeDeltaE, min_weight: minWeight,
                        skin_rule: skinRule ? 1 : 0)
    }
}

/// Bytes que reserva `extractPalette` para el contexto del motor (<= 2 MiB).
public var colorEngineContextSize: Int {
    ce_ctx_size()
}

/// Extrae la paleta dominante de un buffer RGBA8 sRGB (alpha ignorada, no
/// premultiplicada) de `width` x `height` píxeles con `stride` bytes por fila.
/// Reserva un `ce_ctx` con `ce_ctx_size()` (alineado a 16) solo durante la
/// llamada. Toda la lógica está en C (ce_palette_extract); devuelve los
/// swatches ordenados por peso descendente (suma 1). Lanza
/// `ColorEngineError` si el buffer es corto o el motor devuelve un error.
public func extractPalette(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                           options: PaletteOptions = .default) throws -> [Swatch] {
    guard width >= 1, height >= 1, stride >= width * 4 else {
        throw ColorEngineError.engine(code: width >= 1 && height >= 1 ? CE_ERR_STRIDE.rawValue : CE_ERR_DIMS.rawValue)
    }
    // El motor recibe int de 32 bits: rechazar antes de convertir para no hacer trap.
    guard width <= Int(Int32.max), height <= Int(Int32.max), stride <= Int(Int32.max) else {
        throw ColorEngineError.engine(code: stride > Int(Int32.max) ? CE_ERR_STRIDE.rawValue : CE_ERR_DIMS.rawValue)
    }
    let required = (height - 1) * stride + width * 4
    guard let base = rgba.baseAddress, rgba.count >= required else {
        throw ColorEngineError.bufferTooSmall(required: required, actual: rgba.count)
    }
    let size = ce_ctx_size()
    let mem = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { mem.deallocate() }
    guard let ctx = ce_ctx_init(mem, size) else {
        throw ColorEngineError.engine(code: CE_ERR_CTX.rawValue)
    }
    var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                       stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: nil)
    var opts = options.cValue
    var out = [ce_swatch](repeating: ce_swatch(), count: Int(CE_PALETTE_MAX_COLORS))
    let n = out.withUnsafeMutableBufferPointer { buf -> Int32 in
        ce_palette_extract(ctx, &img, &opts, buf.baseAddress, Int32(buf.count))
    }
    if n < 0 {
        throw ColorEngineError.engine(code: n)
    }
    return out.prefix(Int(n)).map(Swatch.init)
}

/// Índice del color del diccionario más cercano (ΔE00) y su distancia.
public func nearestDictionaryColor(_ lab: Lab) -> (index: Int, deltaE: Double) {
    var de = 0.0
    let idx = ce_dict_nearest_color(lab.cValue, &de)
    return (Int(idx), de)
}
