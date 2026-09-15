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
    /// El motor devolvió un código negativo (ce_status de ce.h).
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

/// Validación común de `extractPalette` y `analyze`: dimensiones, stride,
/// rango de Int32 (el motor recibe int de 32 bits: rechazar antes de convertir
/// para no hacer trap) y tamaño mínimo del buffer. Devuelve el puntero base.
private func validateRGBA(_ rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                          stride: Int) throws -> UnsafePointer<UInt8> {
    guard width >= 1, height >= 1, stride >= width * 4 else {
        throw ColorEngineError.engine(code: width >= 1 && height >= 1 ? CE_ERR_STRIDE.rawValue : CE_ERR_DIMS.rawValue)
    }
    guard width <= Int(Int32.max), height <= Int(Int32.max), stride <= Int(Int32.max) else {
        throw ColorEngineError.engine(code: stride > Int(Int32.max) ? CE_ERR_STRIDE.rawValue : CE_ERR_DIMS.rawValue)
    }
    let required = (height - 1) * stride + width * 4
    guard let base = rgba.baseAddress, rgba.count >= required else {
        throw ColorEngineError.bufferTooSmall(required: required, actual: rgba.count)
    }
    return base
}

/// Extrae la paleta dominante de un buffer RGBA8 sRGB (alpha ignorada, no
/// premultiplicada) de `width` x `height` píxeles con `stride` bytes por fila.
/// Reserva un `ce_ctx` con `ce_ctx_size()` (alineado a 16) solo durante la
/// llamada. Toda la lógica está en C (ce_palette_extract); devuelve los
/// swatches ordenados por peso descendente (suma 1). Lanza
/// `ColorEngineError` si el buffer es corto o el motor devuelve un error.
public func extractPalette(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                           options: PaletteOptions = .default) throws -> [Swatch] {
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
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

// MARK: - Diccionario de Wada (accesores sin contexto)

/// Versión del diccionario embebido (sha256 corto de 12 hex); la app la cruza
/// con `dict_version` del dictionary.json del bundle.
public var dictionaryVersion: String {
    String(cString: ce_dict_version())
}

/// Número de combinaciones (348 en el Vol. 1).
public var dictionaryComboCount: Int {
    Int(ce_dict_num_combos())
}

/// Número de colores (159 en el Vol. 1).
public var dictionaryColorCount: Int {
    Int(ce_dict_num_colors())
}

/// Índices de color (ascendentes) de la combinación `id` (1...348); nil si no existe.
public func dictionaryCombo(id: Int) -> [Int]? {
    guard id >= 1, id <= Int(Int32.max) else { return nil }
    var size: UInt8 = 0
    var colors = [UInt8](repeating: UInt8(CE_DICT_NO_COLOR), count: Int(CE_DICT_COMBO_MAX))
    let rc = colors.withUnsafeMutableBufferPointer { buf in
        ce_dict_combo(Int32(id), &size, buf.baseAddress)
    }
    guard rc == 0 else { return nil }
    return colors.prefix(Int(size)).map { Int($0) }
}

/// sRGB8 del color `index` del diccionario; nil fuera de rango.
public func dictionaryColorRGB(index: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
    guard index >= 0, index <= Int(Int32.max) else { return nil }
    var rgb: [UInt8] = [0, 0, 0]
    let rc = rgb.withUnsafeMutableBufferPointer { buf in
        ce_dict_color_rgb(Int32(index), buf.baseAddress)
    }
    guard rc == 0 else { return nil }
    return (rgb[0], rgb[1], rgb[2])
}

/// Lab (D65) del color `index` (ce_dict_color_lab, la misma conversión que la
/// foto); nil fuera de rango.
public func dictionaryColorLab(index: Int) -> Lab? {
    guard index >= 0, index <= Int(Int32.max) else { return nil }
    let c = ce_dict_color_lab(Int32(index))
    return c.L.isNaN ? nil : Lab(c)
}

/// Nombre en inglés (Ridgway) del color `index`; nil fuera de rango.
public func dictionaryColorName(index: Int) -> String? {
    guard index >= 0, index <= Int(Int32.max), let p = ce_dict_color_name(Int32(index)) else { return nil }
    return String(cString: p)
}

// MARK: - Capa 3: match contra el diccionario

/// Opciones de ce_match (ver ce.h): kL/kC/kH de ΔE00 (<= 0 cuenta como 1;
/// kL = 2 es el modo "textiles"), peso del término de cobertura (>= 0) y gap de
/// ambigüedad (score[1] - score[0] < gap => `ambiguous`). Las cinco deben ser
/// finitas; si no, el motor devuelve CE_ERR_OPTS.
public struct MatchOptions: Equatable, Sendable {
    public var kL: Double
    public var kC: Double
    public var kH: Double
    public var coverageLambda: Double
    public var ambiguousGap: Double
    /// Hipótesis de exposición: ganancias 2^EV en pasos de 0,5 EV hasta ±exposureEVMax
    /// (0 = solo la identidad); `exposurePenalty` ΔE por EV de desviación.
    public var exposureEVMax: Double
    public var exposurePenalty: Double
    /// Hipótesis de iluminante (A, D50, D75, F2 adaptados a D65 con Bradford) y su
    /// penalización fija en ΔE.
    public var illuminantSearch: Bool
    public var illuminantPenalty: Double

    /// Valores de ce_match_opts_default (kL 1, kC 1, kH 1, λ 1.0, gap 1.0,
    /// exposición ±1 EV con penalización 2.0, iluminantes activados con penalización 2.0).
    public static var `default`: MatchOptions {
        var o = ce_match_opts()
        ce_match_opts_default(&o)
        return MatchOptions(o)
    }

    public init(kL: Double, kC: Double, kH: Double, coverageLambda: Double, ambiguousGap: Double,
                exposureEVMax: Double = 1.0, exposurePenalty: Double = 2.0,
                illuminantSearch: Bool = true, illuminantPenalty: Double = 2.0) {
        self.kL = kL
        self.kC = kC
        self.kH = kH
        self.coverageLambda = coverageLambda
        self.ambiguousGap = ambiguousGap
        self.exposureEVMax = exposureEVMax
        self.exposurePenalty = exposurePenalty
        self.illuminantSearch = illuminantSearch
        self.illuminantPenalty = illuminantPenalty
    }

    init(_ o: ce_match_opts) {
        self.init(kL: o.kL, kC: o.kC, kH: o.kH, coverageLambda: o.coverage_lambda, ambiguousGap: o.ambiguous_gap,
                  exposureEVMax: o.exposure_ev_max, exposurePenalty: o.exposure_penalty,
                  illuminantSearch: o.illuminant_search != 0, illuminantPenalty: o.illuminant_penalty)
    }

    var cValue: ce_match_opts {
        ce_match_opts(kL: kL, kC: kC, kH: kH, coverage_lambda: coverageLambda, ambiguous_gap: ambiguousGap,
                      exposure_ev_max: exposureEVMax, exposure_penalty: exposurePenalty,
                      illuminant_search: illuminantSearch ? 1 : 0, illuminant_penalty: illuminantPenalty)
    }
}

/// Un candidato del match: id de combinación (1...348) y score (menor = mejor, >= 0).
public struct Hit: Equatable, Hashable, Sendable {
    public var comboId: Int
    public var score: Double

    public init(comboId: Int, score: Double) {
        self.comboId = comboId
        self.score = score
    }

    init(_ h: ce_hit) {
        self.init(comboId: Int(h.combo_id), score: h.score)
    }
}

/// Resultado de `analyze`: paleta (peso descendente, suma 1), los `topK`
/// mejores candidatos (score ascendente, desempate por id), `ambiguous` y el
/// hash FNV-1a (ce_result_hash) del resultado truncado a esos hits: coincide
/// con el "hash" de `ce match --top K` sobre los mismos píxeles, también entre
/// plataformas (el motor lleva su propia libm, `ce_libm.c`: mismos bits en
/// iOS/macOS y WASM).
public struct AnalysisResult: Equatable, Sendable {
    public var swatches: [Swatch]
    public var hits: [Hit]
    public var ambiguous: Bool
    public var hash: UInt64

    public init(swatches: [Swatch], hits: [Hit], ambiguous: Bool, hash: UInt64) {
        self.swatches = swatches
        self.hits = hits
        self.ambiguous = ambiguous
        self.hash = hash
    }
}

/// Máximo de candidatos que devuelve `analyze` (CE_MATCH_MAX_HITS = 10).
public var colorEngineMaxHits: Int {
    Int(CE_MATCH_MAX_HITS)
}

/// Paleta + match contra el diccionario (ce_analyze) sobre un buffer RGBA8
/// sRGB como el de `extractPalette`. `topK` en 1...10 (si no, lanza
/// `.engine(code: CE_ERR_ARG)`); el motor calcula siempre los 10 mejores y
/// aquí se devuelven los `topK` primeros. Reserva un `ce_ctx` solo durante
/// la llamada; nada de lógica de color en Swift.
public func analyze(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                    paletteOptions: PaletteOptions = .default, matchOptions: MatchOptions = .default,
                    topK: Int = 3) throws -> AnalysisResult {
    guard topK >= 1, topK <= Int(CE_MATCH_MAX_HITS) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let size = ce_ctx_size()
    let mem = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { mem.deallocate() }
    guard let ctx = ce_ctx_init(mem, size) else {
        throw ColorEngineError.engine(code: CE_ERR_CTX.rawValue)
    }
    var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                       stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: nil)
    var po = paletteOptions.cValue
    var mo = matchOptions.cValue
    var res = ce_result()
    let rc = ce_analyze(ctx, &img, &po, &mo, &res)
    if rc < 0 {
        throw ColorEngineError.engine(code: rc)
    }
    let nSwatches = Int(res.n_swatches)
    let nHits = min(topK, Int(res.n_hits))
    res.n_hits = Int32(nHits)
    let hash = ce_result_hash(&res)
    let swatches: [Swatch] = withUnsafePointer(to: &res.swatches) { p in
        p.withMemoryRebound(to: ce_swatch.self, capacity: Int(CE_PALETTE_MAX_COLORS)) { q in
            (0..<nSwatches).map { Swatch(q[$0]) }
        }
    }
    let hits: [Hit] = withUnsafePointer(to: &res.hits) { p in
        p.withMemoryRebound(to: ce_hit.self, capacity: Int(CE_MATCH_MAX_HITS)) { q in
            (0..<nHits).map { Hit(q[$0]) }
        }
    }
    return AnalysisResult(swatches: swatches, hits: hits, ambiguous: res.ambiguous != 0, hash: hash)
}
