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
    /// La máscara opcional tiene menos de width * height bytes.
    case maskTooSmall(required: Int, actual: Int)
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
    /// EXPERIMENTO desactivado por defecto (0): fusión de sombras, ΔE00 con
    /// kL = 3 (`CE_PALETTE_LIGHT_MERGE_KL`) < `mergeLightDeltaE` entre centros
    /// tras la fusión normal (tonos de la misma prenda con luz y sombra). <= 0 = apagada.
    public var mergeLightDeltaE: Double

    /// Valores de ce_palette_opts_default (k 6, 20 iteraciones, 5 colores,
    /// lado 256, sigma 0.35, fusión ΔE00 < 5, descarte < 5 %, sin regla de piel,
    /// sin fusión de sombras).
    public static var `default`: PaletteOptions {
        var o = ce_palette_opts()
        ce_palette_opts_default(&o)
        return PaletteOptions(o)
    }

    public init(kInit: Int32, maxIters: Int32, maxColors: Int32, maxSide: Int32,
                centerSigma: Double, mergeDeltaE: Double, minWeight: Double, skinRule: Bool,
                mergeLightDeltaE: Double = 0.0) {
        self.kInit = kInit
        self.maxIters = maxIters
        self.maxColors = maxColors
        self.maxSide = maxSide
        self.centerSigma = centerSigma
        self.mergeDeltaE = mergeDeltaE
        self.minWeight = minWeight
        self.skinRule = skinRule
        self.mergeLightDeltaE = mergeLightDeltaE
    }

    init(_ o: ce_palette_opts) {
        self.init(kInit: o.k_init, maxIters: o.max_iters, maxColors: o.max_colors, maxSide: o.max_side,
                  centerSigma: o.center_sigma, mergeDeltaE: o.merge_de, minWeight: o.min_weight,
                  skinRule: o.skin_rule != 0, mergeLightDeltaE: o.merge_light_de)
    }

    var cValue: ce_palette_opts {
        ce_palette_opts(k_init: kInit, max_iters: maxIters, max_colors: maxColors, max_side: maxSide,
                        center_sigma: centerSigma, merge_de: mergeDeltaE, min_weight: minWeight,
                        skin_rule: skinRule ? 1 : 0, merge_light_de: mergeLightDeltaE)
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

/// Máscara opcional de ce_image: width * height bytes empaquetados sin stride
/// (0 anula el píxel, 255 = peso pleno). nil => sin máscara. Devuelve el
/// puntero base o nil; lanza `maskTooSmall` si el buffer es corto.
private func validateMask(_ mask: UnsafeBufferPointer<UInt8>?, width: Int, height: Int) throws -> UnsafePointer<UInt8>? {
    guard let mask else { return nil }
    let required = width * height
    guard let base = mask.baseAddress, mask.count >= required else {
        throw ColorEngineError.maskTooSmall(required: required, actual: mask.count)
    }
    return base
}

/// Extrae la paleta dominante de un buffer RGBA8 sRGB (alpha ignorada, no
/// premultiplicada) de `width` x `height` píxeles con `stride` bytes por fila.
/// Reserva un `ce_ctx` con `ce_ctx_size()` (alineado a 16) solo durante la
/// llamada. Toda la lógica está en C (ce_palette_extract); devuelve los
/// swatches ordenados por peso descendente (suma 1). `mask` opcional (width *
/// height bytes, sin stride, 0..255: multiplica el peso de cada píxel; la
/// máscara toda a 0 da 1 swatch con el color medio). Lanza `ColorEngineError`
/// si el buffer o la máscara son cortos o el motor devuelve un error.
public func extractPalette(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                           options: PaletteOptions = .default,
                           mask: UnsafeBufferPointer<UInt8>? = nil) throws -> [Swatch] {
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let maskBase = try validateMask(mask, width: width, height: height)
    let size = ce_ctx_size()
    let mem = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { mem.deallocate() }
    guard let ctx = ce_ctx_init(mem, size) else {
        throw ColorEngineError.engine(code: CE_ERR_CTX.rawValue)
    }
    var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                       stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: maskBase)
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
    /// penalización fija en ΔE. DESACTIVADA por defecto desde 2026-09-15 (ADR-009): las
    /// fotos del teléfono ya llegan con balance de blancos y compensar una luz inexistente
    /// giraba tonos (rosa palo + negro -> Nº 067 azul). Sigue disponible con `true`.
    public var illuminantSearch: Bool
    public var illuminantPenalty: Double

    /// Valores de ce_match_opts_default (kL 1, kC 1, kH 1, λ 1.0, gap 1.0,
    /// exposición ±1 EV con penalización 2.0, iluminantes desactivados; penalización 2.0).
    public static var `default`: MatchOptions {
        var o = ce_match_opts()
        ce_match_opts_default(&o)
        return MatchOptions(o)
    }

    public init(kL: Double, kC: Double, kH: Double, coverageLambda: Double, ambiguousGap: Double,
                exposureEVMax: Double = 1.0, exposurePenalty: Double = 2.0,
                illuminantSearch: Bool = false, illuminantPenalty: Double = 2.0) {
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
/// aquí se devuelven los `topK` primeros. `mask` opcional como en
/// `extractPalette` (width * height bytes, 0 anula el píxel). Reserva un
/// `ce_ctx` solo durante la llamada; nada de lógica de color en Swift.
public func analyze(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                    paletteOptions: PaletteOptions = .default, matchOptions: MatchOptions = .default,
                    topK: Int = 3, mask: UnsafeBufferPointer<UInt8>? = nil) throws -> AnalysisResult {
    guard topK >= 1, topK <= Int(CE_MATCH_MAX_HITS) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let maskBase = try validateMask(mask, width: width, height: height)
    let size = ce_ctx_size()
    let mem = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { mem.deallocate() }
    guard let ctx = ce_ctx_init(mem, size) else {
        throw ColorEngineError.engine(code: CE_ERR_CTX.rawValue)
    }
    var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                       stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: maskBase)
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

// MARK: - Máscaras: regiones de ropa y piel adaptativa

extension ColorEngineError {
    /// `.engine(code: CE_ERR_POSE)` (-8): faltan hombros o caderas (ni por
    /// simetría) o la pose es degenerada. Constantes, no casos nuevos: los
    /// `switch` exhaustivos existentes sobre ColorEngineError siguen compilando.
    public static let poseMissing = ColorEngineError.engine(code: CE_ERR_POSE.rawValue)
    /// `.engine(code: CE_ERR_SKIN_SAMPLES)` (-9): menos de 50 muestras de piel.
    public static let tooFewSkinSamples = ColorEngineError.engine(code: CE_ERR_SKIN_SAMPLES.rawValue)
}

/// Articulaciones de la pose en el orden de `ce_joint` (el de
/// VNHumanBodyPoseObservation: cuello = punto medio de los hombros, raíz =
/// punto medio de las caderas). "left" es la izquierda de la persona.
public enum Joint: Int, CaseIterable, Sendable {
    case nose = 0, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, root
}

/// Punto de la pose en píxeles de la máscara (origen arriba-izquierda, y hacia
/// abajo; el centro del píxel (i, j) es (i + 0.5, j + 0.5)). `confidence <= 0`
/// significa ausente.
public struct Keypoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    /// Punto ausente (confidence 0).
    public static let missing = Keypoint(x: 0, y: 0, confidence: 0)
}

/// Pose de una persona: 15 puntos en el orden de `Joint` / `ce_joint`.
public struct Pose: Equatable, Sendable {
    public var joints: [Keypoint]

    public init(joints: [Keypoint]) {
        self.joints = joints
    }

    /// Pose con los 15 puntos ausentes.
    public init() {
        self.joints = Array(repeating: .missing, count: Int(CE_JOINT_COUNT.rawValue))
    }

    public subscript(joint: Joint) -> Keypoint {
        get { joints[joint.rawValue] }
        set { joints[joint.rawValue] = newValue }
    }
}

/// Opciones de `clothingRegions` (ver `ce_region_opts` en ce.h: rangos y
/// geometría). `limbWidth` es el ANCHO total de las cápsulas en anchos de hombros.
public struct RegionOptions: Equatable, Sendable {
    public var minConfidence: Double
    public var torsoMargin: Double
    public var limbWidth: Double
    public var includeUpperArms: Bool
    public var includeForearms: Bool
    public var includeLegs: Bool
    public var includeLowerLegs: Bool

    /// Valores de ce_region_opts_default: confianza mínima 0,3, margen del torso
    /// 0,12, ancho de miembros 0,45, brazos sí, antebrazos no, piernas sí.
    public static var `default`: RegionOptions {
        var o = ce_region_opts()
        ce_region_opts_default(&o)
        return RegionOptions(o)
    }

    public init(minConfidence: Double, torsoMargin: Double, limbWidth: Double, includeUpperArms: Bool,
                includeForearms: Bool, includeLegs: Bool, includeLowerLegs: Bool) {
        self.minConfidence = minConfidence
        self.torsoMargin = torsoMargin
        self.limbWidth = limbWidth
        self.includeUpperArms = includeUpperArms
        self.includeForearms = includeForearms
        self.includeLegs = includeLegs
        self.includeLowerLegs = includeLowerLegs
    }

    init(_ o: ce_region_opts) {
        self.init(minConfidence: o.min_confidence, torsoMargin: o.torso_margin, limbWidth: o.limb_width,
                  includeUpperArms: o.include_upper_arms != 0, includeForearms: o.include_forearms != 0,
                  includeLegs: o.include_legs != 0, includeLowerLegs: o.include_lower_legs != 0)
    }

    var cValue: ce_region_opts {
        ce_region_opts(min_confidence: minConfidence, torso_margin: torsoMargin, limb_width: limbWidth,
                       include_upper_arms: includeUpperArms ? 1 : 0, include_forearms: includeForearms ? 1 : 0,
                       include_legs: includeLegs ? 1 : 0, include_lower_legs: includeLowerLegs ? 1 : 0)
    }
}

/// Dimensiones de máscara representables como `int` de C (el motor exige además
/// 1...CE_IMAGE_MAX_SIDE y devuelve CE_ERR_ARG / CE_ERR_DIMS si no).
private func maskDimsFit(width: Int, height: Int) -> Bool {
    width >= 1 && height >= 1 && width <= Int(CE_IMAGE_MAX_SIDE) && height <= Int(CE_IMAGE_MAX_SIDE)
}

/// Recorta la máscara de una persona (`width` x `height` bytes, 0..255, sin
/// stride) a su ropa según la pose: `min(máscara, región)` con la región de
/// `ce_mask_clothing_regions` (torso expandido + cápsulas de brazos y piernas;
/// nunca cabeza ni manos). Si falta un hombro o una cadera se estima por
/// simetría con el cuello / la raíz. Devuelve la máscara nueva y los píxeles
/// > 0. Lanza `.engine(code: CE_ERR_POSE)` si faltan hombros o caderas,
/// `.engine(code: CE_ERR_ARG)` con opciones o dimensiones inválidas o una pose
/// que no tiene 15 puntos, y `.maskTooSmall` si la máscara es corta.
public func clothingRegions(pose: Pose, options: RegionOptions = .default, mask: [UInt8], width: Int,
                            height: Int) throws -> (mask: [UInt8], pixels: Int) {
    guard pose.joints.count == Int(CE_JOINT_COUNT.rawValue), maskDimsFit(width: width, height: height) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let count = width * height
    guard mask.count >= count else {
        throw ColorEngineError.maskTooSmall(required: count, actual: mask.count)
    }
    var cPose = ce_pose()
    withUnsafeMutableBytes(of: &cPose.k) { raw in
        let kp = raw.bindMemory(to: ce_keypoint.self)
        for (i, j) in pose.joints.enumerated() {
            kp[i] = ce_keypoint(x: j.x, y: j.y, confidence: j.confidence)
        }
    }
    var opts = options.cValue
    var out = Array(mask.prefix(count))
    let rc = out.withUnsafeMutableBufferPointer { buf in
        ce_mask_clothing_regions(&cPose, &opts, buf.baseAddress, Int32(width), Int32(height))
    }
    if rc < 0 {
        throw ColorEngineError.engine(code: rc)
    }
    return (out, Int(rc))
}

/// Fallback sin pose (`ce_mask_cut_head`): anula la franja superior del bbox
/// de la máscara, `fraction` de su alto (se acota a 0...0,5; NaN cuenta como 0).
/// No lanza: con dimensiones inválidas o una máscara corta devuelve la máscara
/// sin tocar y `pixels` = CE_ERR_ARG (-1).
public func cutHead(mask: [UInt8], width: Int, height: Int, fraction: Double) -> (mask: [UInt8], pixels: Int) {
    guard maskDimsFit(width: width, height: height), mask.count >= width * height else {
        return (mask, Int(CE_ERR_ARG.rawValue))
    }
    let f = fraction.isNaN ? 0 : min(max(fraction, 0), 0.5)
    var out = Array(mask.prefix(width * height))
    let rc = out.withUnsafeMutableBufferPointer { buf in
        ce_mask_cut_head(buf.baseAddress, Int32(width), Int32(height), f)
    }
    return rc < 0 ? (mask, Int(rc)) : (out, Int(rc))
}

/// Modelo gaussiano de piel en CIELAB ajustado a una muestra (p. ej. las
/// mejillas): media, covarianza regularizada (+ CE_SKIN_COV_EPSILON · I) y su
/// inversa, row-major 3x3, y número de muestras.
public struct SkinModel: Equatable, Sendable {
    public var mean: Lab
    public var covariance: [Double]
    public var inverseCovariance: [Double]
    public var sampleCount: Int

    public init(mean: Lab, covariance: [Double], inverseCovariance: [Double], sampleCount: Int) {
        self.mean = mean
        self.covariance = covariance
        self.inverseCovariance = inverseCovariance
        self.sampleCount = sampleCount
    }

    init(_ m: ce_skin_model) {
        var c = m
        let cov = withUnsafeBytes(of: &c.cov) { Array($0.bindMemory(to: Double.self)) }
        let inv = withUnsafeBytes(of: &c.inv_cov) { Array($0.bindMemory(to: Double.self)) }
        self.init(mean: Lab(m.mean), covariance: cov, inverseCovariance: inv, sampleCount: Int(m.n))
    }

    /// nil si las matrices no tienen 9 elementos o `sampleCount` no cabe en Int32.
    var cValue: ce_skin_model? {
        guard covariance.count == 9, inverseCovariance.count == 9,
              sampleCount >= Int(Int32.min), sampleCount <= Int(Int32.max) else { return nil }
        var m = ce_skin_model()
        m.mean = mean.cValue
        m.n = Int32(sampleCount)
        withUnsafeMutableBytes(of: &m.cov) { raw in
            let p = raw.bindMemory(to: Double.self)
            for i in 0..<9 { p[i] = covariance[i] }
        }
        withUnsafeMutableBytes(of: &m.inv_cov) { raw in
            let p = raw.bindMemory(to: Double.self)
            for i in 0..<9 { p[i] = inverseCovariance[i] }
        }
        return m
    }
}

/// Opciones de `excludeSkin`: distancia de Mahalanobis máxima (2,5) y fracción
/// máxima de la máscara que se puede excluir antes de que salte la
/// salvaguarda (0,35).
public struct SkinOptions: Equatable, Sendable {
    public var maxMahalanobis: Double
    public var maxExcludedFraction: Double

    public static var `default`: SkinOptions {
        var o = ce_skin_opts()
        ce_skin_opts_default(&o)
        return SkinOptions(maxMahalanobis: o.max_mahalanobis, maxExcludedFraction: o.max_excluded_fraction)
    }

    public init(maxMahalanobis: Double, maxExcludedFraction: Double) {
        self.maxMahalanobis = maxMahalanobis
        self.maxExcludedFraction = maxExcludedFraction
    }

    var cValue: ce_skin_opts {
        ce_skin_opts(max_mahalanobis: maxMahalanobis, max_excluded_fraction: maxExcludedFraction)
    }
}

/// Ajusta el modelo de piel (`ce_skin_model_fit`) con los píxeles del buffer
/// RGBA8 sRGB cuya `sampleMask` (width * height bytes) vale >= 128. Lanza
/// `.engine(code: CE_ERR_SKIN_SAMPLES)` con menos de 50 muestras, los errores
/// de imagen de `extractPalette` y `.maskTooSmall` si la muestra es corta.
public func fitSkinModel(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                         sampleMask: [UInt8]) throws -> SkinModel {
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    guard sampleMask.count >= width * height else {
        throw ColorEngineError.maskTooSmall(required: width * height, actual: sampleMask.count)
    }
    var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                       stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: nil)
    var model = ce_skin_model()
    let rc = sampleMask.withUnsafeBufferPointer { s in
        ce_skin_model_fit(&img, s.baseAddress, &model)
    }
    if rc != 0 {
        throw ColorEngineError.engine(code: rc)
    }
    return SkinModel(model)
}

/// Quita de `mask` los píxeles cuyo color está a distancia de Mahalanobis <=
/// `options.maxMahalanobis` del modelo (`ce_mask_exclude_skin`). Si se fuera a
/// excluir más de `maxExcludedFraction` de la máscara (prenda parecida a la
/// piel) no toca nada y `guardTriggered` es true. `excluded` = píxeles > 0
/// que pasaron a 0. Lanza `.engine(code:)` (CE_ERR_ARG con opciones o modelo
/// inválidos, CE_ERR_SKIN_SAMPLES con un modelo de < 50 muestras), errores de
/// imagen y `.maskTooSmall`.
public func excludeSkin(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                        model: SkinModel, options: SkinOptions = .default,
                        mask: [UInt8]) throws -> (mask: [UInt8], excluded: Int, guardTriggered: Bool) {
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let count = width * height
    guard mask.count >= count else {
        throw ColorEngineError.maskTooSmall(required: count, actual: mask.count)
    }
    guard var cModel = model.cValue else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                       stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: nil)
    var opts = options.cValue
    var out = Array(mask.prefix(count))
    let before = out.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    let rc = out.withUnsafeMutableBufferPointer { buf in
        ce_mask_exclude_skin(&img, &cModel, &opts, buf.baseAddress)
    }
    if rc < 0 {
        throw ColorEngineError.engine(code: rc)
    }
    let after = out.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    return (out, before - after, rc == CE_SKIN_GUARD)
}

// MARK: - Separación de instancias fusionadas

/// Semillas máximas por instancia (`CE_SPLIT_MAX_SEEDS`).
public let splitMaxSeeds = Int(CE_SPLIT_MAX_SEEDS)

/// Semilla de una persona (`ce_person_seed`): eje del cuerpo en píxeles de la
/// máscara, de arriba (`x0`, `y0`: cuello o base de la cara) a abajo (`x1`,
/// `y1`: caderas o extrapolado), y semiancho del cuerpo (> 0, píxeles).
public struct PersonSeed: Equatable, Hashable, Sendable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double
    public var halfWidth: Double

    public init(x0: Double, y0: Double, x1: Double, y1: Double, halfWidth: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        self.halfWidth = halfWidth
    }

    var cValue: ce_person_seed {
        ce_person_seed(x0: x0, y0: y0, x1: x1, y1: y1, half_width: halfWidth)
    }
}

/// Separa una máscara de instancia que junta a varias personas
/// (`ce_mask_split_instance`): cada píxel con máscara >= 128 recibe 1 + el
/// índice de la semilla con menor distancia al eje / semiancho (empate: índice
/// menor); el resto, 0. `count` = etiquetas con al menos un píxel. Lanza
/// `.engine(code: CE_ERR_ARG)` con 0 o más de `splitMaxSeeds` semillas,
/// dimensiones fuera de 1...CE_IMAGE_MAX_SIDE o semillas no finitas, fuera de
/// ±CE_POSE_COORD_MAX o con semiancho <= 0, y `.maskTooSmall` si la máscara
/// es corta.
public func splitInstance(mask: [UInt8], width: Int, height: Int,
                          seeds: [PersonSeed]) throws -> (labels: [UInt8], count: Int) {
    guard maskDimsFit(width: width, height: height), seeds.count >= 1, seeds.count <= splitMaxSeeds else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let count = width * height
    guard mask.count >= count else {
        throw ColorEngineError.maskTooSmall(required: count, actual: mask.count)
    }
    let cSeeds = seeds.map(\.cValue)
    var labels = [UInt8](repeating: 0, count: count)
    let rc = mask.withUnsafeBufferPointer { m in
        cSeeds.withUnsafeBufferPointer { s in
            labels.withUnsafeMutableBufferPointer { out in
                ce_mask_split_instance(m.baseAddress, Int32(width), Int32(height), s.baseAddress,
                                       Int32(s.count), out.baseAddress)
            }
        }
    }
    if rc < 0 {
        throw ColorEngineError.engine(code: rc)
    }
    return (labels, Int(rc))
}

// MARK: - Capas de depuración

/// Etiqueta de un píxel reducido con peso 0 en `PaletteDebugLayers.labelMap` y
/// `clusterMap` (máscara, piel o fuera del sujeto).
public let paletteLabelNone = UInt8(CE_LABEL_NONE)
/// Etiqueta de un píxel cuyo cluster se descartó (min_weight) o se recortó (max_colors).
public let paletteLabelDiscarded = UInt8(CE_LABEL_DISCARDED)

/// Destino de un cluster de Lloyd.
public enum ClusterFate: Int, Sendable {
    /// Representante de su grupo: es el swatch `finalIndex`.
    case kept = 0
    /// Fusionado (ΔE00 < merge_de) en el swatch `finalIndex`.
    case merged = 1
    /// Su grupo pesaba menos que min_weight.
    case discarded = 2
    /// Su grupo quedó fuera del recorte a max_colors.
    case truncated = 3
}

/// Cluster de Lloyd tras converger y antes de fusionar (`ce_cluster_debug`).
public struct ClusterDebug: Equatable, Sendable {
    public var lab: Lab
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    /// Peso del cluster sobre el total antes de fusionar y descartar.
    public var weight: Double
    public var fate: ClusterFate
    /// Swatch de la paleta al que alimenta (nil si se descartó o recortó).
    public var finalIndex: Int?
    /// Índice (en `PaletteDebug.clusters`) del representante de su grupo de fusión.
    public var groupHead: Int

    init(_ c: ce_cluster_debug) {
        lab = Lab(c.lab)
        r = c.rgb.0
        g = c.rgb.1
        b = c.rgb.2
        weight = c.weight
        fate = ClusterFate(rawValue: Int(c.fate)) ?? .discarded
        finalIndex = c.final_index >= 0 ? Int(c.final_index) : nil
        groupHead = Int(c.group_head)
    }

    /// "#rrggbb".
    public var hex: String {
        Swatch(lab: lab, r: r, g: g, b: b, weight: weight).hex
    }
}

/// Resumen de la extracción (`ce_palette_debug`).
public struct PaletteDebug: Equatable, Sendable {
    public var reducedWidth: Int
    public var reducedHeight: Int
    public var clusters: [ClusterDebug]
    public var lloydIterations: Int
    public var totalWeight: Double
    public var zeroWeightFraction: Double
    /// Sigma de la gaussiana al centro en píxeles de la reducida (0 = uniforme).
    public var centerSigmaPx: Double
    public var swatchCount: Int
}

/// Swatch i frente a la combinación explicada (hipótesis ganadora).
public struct SwatchExplanation: Equatable, Sendable {
    /// Índice de color del diccionario más cercano dentro de la combinación.
    public var nearestColorIndex: Int
    public var deltaE: Double
}

/// Color j de la combinación frente a la paleta (hipótesis ganadora).
public struct ColorExplanation: Equatable, Sendable {
    public var colorIndex: Int
    public var nearestSwatch: Int
    public var deltaE: Double
}

/// Por qué una combinación tiene su score (`ce_match_explain_combo`):
/// `score == fitTerm + coverageTerm + hypothesisPenalty` y `score` es bit a
/// bit el de `analyze` para esa combinación.
public struct MatchExplanation: Equatable, Sendable {
    public var comboId: Int
    public var score: Double
    public var fitTerm: Double
    public var coverageTerm: Double
    public var hypothesisPenalty: Double
    /// EV de la hipótesis de exposición ganadora.
    public var exposureEV: Double
    /// -1 sin adaptación de iluminante; si no, el `ce_illuminant` (0 A, 1 D50, 3 D75, 4 F2).
    public var illuminant: Int
    public var perSwatch: [SwatchExplanation]
    public var perColor: [ColorExplanation]

    init(_ e: ce_match_explain) {
        var c = e
        comboId = Int(e.combo_id)
        score = e.score
        fitTerm = e.fit_term
        coverageTerm = e.coverage_term
        hypothesisPenalty = e.hypothesis_penalty
        exposureEV = e.exposure_ev
        illuminant = Int(e.illuminant)
        let ns = max(0, min(Int(e.n_swatches), Int(CE_PALETTE_MAX_COLORS)))
        let nc = max(0, min(Int(e.combo_size), Int(CE_DICT_MAX_COLORS)))
        perSwatch = withUnsafeBytes(of: &c.per_swatch) { raw in
            raw.bindMemory(to: ce_swatch_explain.self).prefix(ns).map {
                SwatchExplanation(nearestColorIndex: Int($0.nearest_color_index), deltaE: $0.de)
            }
        }
        perColor = withUnsafeBytes(of: &c.per_color) { raw in
            raw.bindMemory(to: ce_color_explain.self).prefix(nc).map {
                ColorExplanation(colorIndex: Int($0.color_index), nearestSwatch: Int($0.nearest_swatch), deltaE: $0.de)
            }
        }
    }
}

/// Todas las capas de un único análisis (un único `ce_ctx`): el resultado de
/// `analyze`, el resumen de clusters y las capas por píxel de la imagen
/// reducida (`reducedWidth` x `reducedHeight`, fila a fila):
/// - `reducedRGB`: lo que ve el motor tras el box-downscale (3 bytes por píxel).
/// - `weightMap`: peso final (máscara x gaussiana x piel) escalado a 0...255.
/// - `labelMap`: swatch al que alimenta cada píxel, `paletteLabelNone` o `paletteLabelDiscarded`.
/// - `clusterMap`: cluster de Lloyd de cada píxel (índice en `debug.clusters`) o `paletteLabelNone`.
/// - `explanations`: `MatchExplanation` de cada hit de `analysis.hits`, en orden.
public struct PaletteDebugLayers: Sendable {
    public var analysis: AnalysisResult
    public var debug: PaletteDebug
    public var reducedRGB: [UInt8]
    public var weightMap: [UInt8]
    public var labelMap: [UInt8]
    public var clusterMap: [UInt8]
    public var explanations: [MatchExplanation]
}

/// `AnalysisResult` de un `ce_result` truncado a `topK` hits (hash incluido).
private func analysisResult(from res: inout ce_result, topK: Int) -> AnalysisResult {
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

/// Reserva un `ce_ctx` alineado a 16 durante `body`.
private func withEngineContext<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    let size = ce_ctx_size()
    let mem = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { mem.deallocate() }
    guard let ctx = ce_ctx_init(mem, size) else {
        throw ColorEngineError.engine(code: CE_ERR_CTX.rawValue)
    }
    return try body(ctx)
}

/// `analyze` + todas las capas de depuración en la misma llamada y el mismo
/// contexto: la paleta, los hits y el hash son idénticos a los de `analyze`
/// con los mismos argumentos. Mismos errores que `analyze`.
public func paletteDebugLayers(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                               paletteOptions: PaletteOptions = .default, matchOptions: MatchOptions = .default,
                               topK: Int = 3, mask: UnsafeBufferPointer<UInt8>? = nil) throws -> PaletteDebugLayers {
    guard topK >= 1, topK <= Int(CE_MATCH_MAX_HITS) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let maskBase = try validateMask(mask, width: width, height: height)
    return try withEngineContext { ctx in
        var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                           stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: maskBase)
        var po = paletteOptions.cValue
        var mo = matchOptions.cValue
        var res = ce_result()
        let rc = ce_analyze(ctx, &img, &po, &mo, &res)
        if rc < 0 {
            throw ColorEngineError.engine(code: rc)
        }
        let fullSwatches = res.swatches
        let nSwatches = res.n_swatches
        let analysis = analysisResult(from: &res, topK: topK)

        var info = ce_palette_debug()
        let irc = ce_palette_debug_info(ctx, &info)
        if irc != 0 {
            throw ColorEngineError.engine(code: irc)
        }
        let rw = Int(info.reduced_width), rh = Int(info.reduced_height)
        let clusters: [ClusterDebug] = withUnsafeBytes(of: &info.clusters) { raw in
            raw.bindMemory(to: ce_cluster_debug.self).prefix(Int(info.n_clusters)).map(ClusterDebug.init)
        }
        let debug = PaletteDebug(reducedWidth: rw, reducedHeight: rh, clusters: clusters,
                                 lloydIterations: Int(info.lloyd_iterations), totalWeight: info.total_weight,
                                 zeroWeightFraction: info.zero_weight_fraction,
                                 centerSigmaPx: info.center_sigma_px, swatchCount: Int(info.n_swatches))
        func layer(_ bytesPerPixel: Int, _ fn: (OpaquePointer, UnsafeMutablePointer<UInt8>?, Int) -> Int32) throws -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: rw * rh * bytesPerPixel)
            let n = buf.withUnsafeMutableBufferPointer { fn(ctx, $0.baseAddress, $0.count) }
            if n < 0 {
                throw ColorEngineError.engine(code: n)
            }
            return buf
        }
        let reduced = try layer(3) { ce_debug_reduced_rgb($0, $1, $2) }
        let weights = try layer(1) { ce_debug_weight_map($0, $1, $2) }
        let labels = try layer(1) { ce_debug_label_map($0, $1, $2) }
        let clusterMap = try layer(1) { ce_debug_cluster_map($0, $1, $2) }

        var explanations: [MatchExplanation] = []
        var sw = fullSwatches
        for hit in analysis.hits {
            var e = ce_match_explain()
            let erc = withUnsafePointer(to: &sw) { p in
                p.withMemoryRebound(to: ce_swatch.self, capacity: Int(CE_PALETTE_MAX_COLORS)) { q in
                    ce_match_explain_combo(ctx, q, nSwatches, &mo, Int32(hit.comboId), &e)
                }
            }
            if erc != 0 {
                throw ColorEngineError.engine(code: erc)
            }
            explanations.append(MatchExplanation(e))
        }
        return PaletteDebugLayers(analysis: analysis, debug: debug, reducedRGB: reduced, weightMap: weights,
                                  labelMap: labels, clusterMap: clusterMap, explanations: explanations)
    }
}

/// Explica el score de la combinación `comboId` frente a una paleta
/// (`ce_match_explain_combo`, sin extracción: reserva un contexto solo para la
/// caché Lab). Con la paleta y las opciones de `analyze`, `score` es bit a bit
/// el del hit correspondiente. Lanza `.engine(code: CE_ERR_ARG)` con 0 o más
/// de 8 swatches, valores no finitos o `comboId` fuera de 1...348, y
/// `.engine(code: CE_ERR_OPTS)` con opciones inválidas.
public func explainMatch(swatches: [Swatch], options: MatchOptions = .default,
                         comboId: Int) throws -> MatchExplanation {
    guard !swatches.isEmpty, swatches.count <= Int(CE_PALETTE_MAX_COLORS),
          comboId >= 1, comboId <= Int(Int32.max) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    return try withEngineContext { ctx in
        let cs = swatches.map { ce_swatch(lab: $0.lab.cValue, rgb: ($0.r, $0.g, $0.b), weight: $0.weight) }
        var mo = options.cValue
        var e = ce_match_explain()
        let rc = cs.withUnsafeBufferPointer { buf in
            ce_match_explain_combo(ctx, buf.baseAddress, Int32(buf.count), &mo, Int32(comboId), &e)
        }
        if rc != 0 {
            throw ColorEngineError.engine(code: rc)
        }
        return MatchExplanation(e)
    }
}

// MARK: - Paleta por prenda

/// Región de un swatch de prenda (`CE_GARMENT_REGION_*`).
public enum GarmentRegion: Int, Sendable {
    /// Sin mapa de regiones (una sola región con toda la máscara).
    case none = 0
    /// Parte de arriba: torso y brazos superiores.
    case upper = 1
    /// Parte de abajo: caderas a tobillos.
    case lower = 2
    /// Prenda entera: arriba y abajo eran la misma prenda (vestido, mono).
    case whole = 3
}

/// Opciones de la paleta por prenda (`ce_garment_opts`; rangos y semántica en ce.h).
///
/// La agrupación de tonos del mismo tejido con distinta luz (enlace COMPLETO, sombra neutra o
/// cromática de exterior, veto de mezcla) y la regla del degradado son constantes del motor, no
/// opciones: `CE_GARMENT_SHADE_S_MIN`, `CE_GARMENT_SHADE_LIT_DE`, `CE_GARMENT_SKY_W_MAX`,
/// `CE_GARMENT_SKY_W_SLOPE` y `CE_GARMENT_GRADIENT_*` en ce.h, con sus límites conocidos.
public struct GarmentOptions: Equatable, Sendable {
    /// kL de ΔE00 al agrupar tonos del mismo color con distinta luz.
    public var shadeKL: Double
    /// Umbral de la agrupación de sombras; tonos iluminados de arriba y abajo con
    /// ΔE00 (kL = 1) menor se fusionan en `.whole`. <= 0 = sin agrupar por sombra.
    public var shadeMergeDeltaE: Double
    /// Percentiles de L* (0...1) del tono iluminado de cada grupo.
    public var litLowPercentile: Double
    public var litHighPercentile: Double
    /// Cuota mínima en su región de un segundo color (prenda bicolor). Un color que es el
    /// EXTREMO DE UN DEGRADADO (tie-dye: hay tonos de mezcla entre los dos) se conserva con una
    /// cuota menor, `CE_GARMENT_GRADIENT_MIN_SHARE` (ver ce.h).
    public var secondaryMinShare: Double
    /// Colores por región (1...8).
    public var maxColorsPerRegion: Int32

    /// Valores de `ce_garment_opts_default` (kL 3, umbral 6,5, percentiles 0,75-0,95,
    /// segundo color >= 25 %, 2 colores por región).
    public static var `default`: GarmentOptions {
        var o = ce_garment_opts()
        ce_garment_opts_default(&o)
        return GarmentOptions(o)
    }

    public init(shadeKL: Double, shadeMergeDeltaE: Double, litLowPercentile: Double, litHighPercentile: Double,
                secondaryMinShare: Double, maxColorsPerRegion: Int32) {
        self.shadeKL = shadeKL
        self.shadeMergeDeltaE = shadeMergeDeltaE
        self.litLowPercentile = litLowPercentile
        self.litHighPercentile = litHighPercentile
        self.secondaryMinShare = secondaryMinShare
        self.maxColorsPerRegion = maxColorsPerRegion
    }

    init(_ o: ce_garment_opts) {
        self.init(shadeKL: o.shade_kL, shadeMergeDeltaE: o.shade_merge_de, litLowPercentile: o.lit_low_pct,
                  litHighPercentile: o.lit_high_pct, secondaryMinShare: o.secondary_min_share,
                  maxColorsPerRegion: o.max_colors_per_region)
    }

    var cValue: ce_garment_opts {
        ce_garment_opts(shade_kL: shadeKL, shade_merge_de: shadeMergeDeltaE, lit_low_pct: litLowPercentile,
                        lit_high_pct: litHighPercentile, secondary_min_share: secondaryMinShare,
                        max_colors_per_region: maxColorsPerRegion)
    }
}

/// Swatch de prenda (`ce_garment_swatch`): el color (tono iluminado del grupo) con su
/// peso final, la región, `regionShare` (la cuota de esa región sobre el área que cubre
/// el MAPA de regiones, no sobre la máscara: las cuotas de las regiones suman 1, así que
/// coinciden con su cuota en la máscara solo cuando el mapa la cubre entera, como hace
/// SubjectKit) y cuántos clusters de Lloyd (tonos de luz y sombra) se agruparon en él.
public struct GarmentSwatch: Equatable, Sendable {
    public var swatch: Swatch
    public var region: GarmentRegion
    public var regionShare: Double
    public var mergedClusterCount: Int

    public init(swatch: Swatch, region: GarmentRegion, regionShare: Double, mergedClusterCount: Int) {
        self.swatch = swatch
        self.region = region
        self.regionShare = regionShare
        self.mergedClusterCount = mergedClusterCount
    }

    init(_ g: ce_garment_swatch) {
        self.init(swatch: Swatch(g.swatch), region: GarmentRegion(rawValue: Int(g.region)) ?? .none,
                  regionShare: g.region_share, mergedClusterCount: Int(g.n_merged_clusters))
    }

    var cValue: ce_garment_swatch {
        ce_garment_swatch(swatch: ce_swatch(lab: swatch.lab.cValue, rgb: (swatch.r, swatch.g, swatch.b),
                                            weight: swatch.weight),
                          region: Int32(region.rawValue), region_share: regionShare,
                          n_merged_clusters: Int32(mergedClusterCount))
    }
}

/// Máximo de regiones del mapa de prendas (`CE_GARMENT_MAX_REGIONS` = 2).
public var garmentMaxRegions: Int {
    Int(CE_GARMENT_MAX_REGIONS)
}

/// Mapa de regiones opcional: width * height bytes (0 fuera, 1 arriba, 2 abajo). Lanza
/// `maskTooSmall` si es corto (el mismo error que la máscara: sin casos nuevos).
private func validateRegions(_ regions: UnsafeBufferPointer<UInt8>?, width: Int, height: Int) throws -> UnsafePointer<UInt8>? {
    try validateMask(regions, width: width, height: height)
}

/// FNV-1a de los swatches de prenda (`ce_garment_hash`): el "hash" de `ce garments --json`.
public func garmentHash(_ garments: [GarmentSwatch]) -> UInt64 {
    let cs = garments.map(\.cValue)
    return cs.withUnsafeBufferPointer { ce_garment_hash($0.baseAddress, Int32($0.count)) }
}

/// Paleta por prenda (`ce_palette_extract_garments`) de un buffer RGBA8 sRGB como el de
/// `extractPalette`: `mask` es la máscara del sujeto y `regions` el mapa de prendas de
/// `garmentRegions` (width * height bytes; nil = una sola región con toda la máscara,
/// swatches con región `.none`). `regionCount` en 1...`garmentMaxRegions` cuando hay mapa.
/// Devuelve los swatches ordenados por peso (suma 1): un color por prenda lisa (tono
/// iluminado), dos si es bicolor, `.whole` si arriba y abajo son la misma prenda.
/// Lanza `.engine(code:)` con los errores del motor (`CE_ERR_ARG` con `regionCount`
/// fuera de rango, `CE_ERR_OPTS` con opciones inválidas) y `bufferTooSmall` /
/// `maskTooSmall` con buffers cortos.
public func extractGarments(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                            paletteOptions: PaletteOptions = .default, garmentOptions: GarmentOptions = .default,
                            mask: UnsafeBufferPointer<UInt8>? = nil, regions: UnsafeBufferPointer<UInt8>? = nil,
                            regionCount: Int = 2) throws -> [GarmentSwatch] {
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let maskBase = try validateMask(mask, width: width, height: height)
    let regionsBase = try validateRegions(regions, width: width, height: height)
    guard regionCount >= Int(Int32.min), regionCount <= Int(Int32.max) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    return try withEngineContext { ctx in
        var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                           stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: maskBase)
        var po = paletteOptions.cValue
        var go = garmentOptions.cValue
        var out = [ce_garment_swatch](repeating: ce_garment_swatch(), count: Int(CE_PALETTE_MAX_COLORS))
        let n = out.withUnsafeMutableBufferPointer { buf -> Int32 in
            ce_palette_extract_garments(ctx, &img, regionsBase, Int32(regionCount), &po, &go, buf.baseAddress,
                                        Int32(buf.count))
        }
        if n < 0 {
            throw ColorEngineError.engine(code: n)
        }
        return out.prefix(Int(n)).map(GarmentSwatch.init)
    }
}

/// Resultado de `analyzeGarments`: el análisis (swatches de prenda como paleta, hits,
/// `ambiguous` y hash de `ce_result_hash`, igual que `result_hash` de
/// `ce garments --match --top K`) y los swatches con su región.
public struct GarmentAnalysisResult: Equatable, Sendable {
    public var analysis: AnalysisResult
    public var garments: [GarmentSwatch]

    public init(analysis: AnalysisResult, garments: [GarmentSwatch]) {
        self.analysis = analysis
        self.garments = garments
    }
}

/// Paleta por prenda + match contra el diccionario (`ce_analyze_garments`; el match no
/// cambia, recibe los swatches de prenda). Argumentos y errores como `extractGarments`
/// y `analyze` (`topK` en 1...10).
public func analyzeGarments(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                            paletteOptions: PaletteOptions = .default, garmentOptions: GarmentOptions = .default,
                            matchOptions: MatchOptions = .default, topK: Int = 3,
                            mask: UnsafeBufferPointer<UInt8>? = nil, regions: UnsafeBufferPointer<UInt8>? = nil,
                            regionCount: Int = 2) throws -> GarmentAnalysisResult {
    try garmentAnalysis(rgba: rgba, width: width, height: height, stride: stride, paletteOptions: paletteOptions,
                        garmentOptions: garmentOptions, matchOptions: matchOptions, topK: topK, mask: mask,
                        regions: regions, regionCount: regionCount) { _, result, _ in result }
}

/// Todas las capas de un análisis por prendas en el mismo contexto: las de
/// `PaletteDebugLayers` (con los swatches de prenda como paleta; `labelMap` y
/// `clusterMap` se refieren a ellos) más la capa "Prendas": `garmentMap` (swatch de
/// prenda por píxel reducido o `paletteLabelNone`) y `regionMap` (región por píxel
/// reducido: 1 arriba, 2 abajo, 3 prenda entera, 0 sin mapa, `paletteLabelNone` fuera).
/// Los clusters de `layers.debug` llevan su grupo de tonos en `groupHead`.
public struct GarmentDebugLayers: Sendable {
    public var result: GarmentAnalysisResult
    public var layers: PaletteDebugLayers
    public var garmentMap: [UInt8]
    public var regionMap: [UInt8]
}

/// `analyzeGarments` + capas de depuración (mismos argumentos y errores; el resultado
/// es idéntico al de `analyzeGarments`).
public func garmentDebugLayers(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                               paletteOptions: PaletteOptions = .default, garmentOptions: GarmentOptions = .default,
                               matchOptions: MatchOptions = .default, topK: Int = 3,
                               mask: UnsafeBufferPointer<UInt8>? = nil, regions: UnsafeBufferPointer<UInt8>? = nil,
                               regionCount: Int = 2) throws -> GarmentDebugLayers {
    try garmentAnalysis(rgba: rgba, width: width, height: height, stride: stride, paletteOptions: paletteOptions,
                        garmentOptions: garmentOptions, matchOptions: matchOptions, topK: topK, mask: mask,
                        regions: regions, regionCount: regionCount) { ctx, result, cResult in
        var res = cResult
        var mo = matchOptions.cValue
        var info = ce_palette_debug()
        let irc = ce_palette_debug_info(ctx, &info)
        if irc != 0 {
            throw ColorEngineError.engine(code: irc)
        }
        let rw = Int(info.reduced_width), rh = Int(info.reduced_height)
        let clusters: [ClusterDebug] = withUnsafeBytes(of: &info.clusters) { raw in
            raw.bindMemory(to: ce_cluster_debug.self).prefix(Int(info.n_clusters)).map(ClusterDebug.init)
        }
        let debug = PaletteDebug(reducedWidth: rw, reducedHeight: rh, clusters: clusters,
                                 lloydIterations: Int(info.lloyd_iterations), totalWeight: info.total_weight,
                                 zeroWeightFraction: info.zero_weight_fraction,
                                 centerSigmaPx: info.center_sigma_px, swatchCount: Int(info.n_swatches))
        func layer(_ bytesPerPixel: Int, _ fn: (OpaquePointer, UnsafeMutablePointer<UInt8>?, Int) -> Int32) throws -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: rw * rh * bytesPerPixel)
            let n = buf.withUnsafeMutableBufferPointer { fn(ctx, $0.baseAddress, $0.count) }
            if n < 0 {
                throw ColorEngineError.engine(code: n)
            }
            return buf
        }
        let reduced = try layer(3) { ce_debug_reduced_rgb($0, $1, $2) }
        let weights = try layer(1) { ce_debug_weight_map($0, $1, $2) }
        let labels = try layer(1) { ce_debug_label_map($0, $1, $2) }
        let clusterMap = try layer(1) { ce_debug_cluster_map($0, $1, $2) }
        let garmentMap = try layer(1) { ce_debug_garment_map($0, $1, $2) }
        let regionMap = try layer(1) { ce_debug_region_map($0, $1, $2) }
        var explanations: [MatchExplanation] = []
        let nSwatches = res.n_swatches
        for hit in result.analysis.hits {
            var e = ce_match_explain()
            let erc = withUnsafePointer(to: &res.swatches) { p in
                p.withMemoryRebound(to: ce_swatch.self, capacity: Int(CE_PALETTE_MAX_COLORS)) { q in
                    ce_match_explain_combo(ctx, q, nSwatches, &mo, Int32(hit.comboId), &e)
                }
            }
            if erc != 0 {
                throw ColorEngineError.engine(code: erc)
            }
            explanations.append(MatchExplanation(e))
        }
        let layers = PaletteDebugLayers(analysis: result.analysis, debug: debug, reducedRGB: reduced,
                                        weightMap: weights, labelMap: labels, clusterMap: clusterMap,
                                        explanations: explanations)
        return GarmentDebugLayers(result: result, layers: layers, garmentMap: garmentMap, regionMap: regionMap)
    }
}

/// Núcleo común de `analyzeGarments` y `garmentDebugLayers`: valida, reserva el
/// contexto, llama a `ce_analyze_garments` y pasa a `body` el contexto aún vivo.
private func garmentAnalysis<T>(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int,
                                paletteOptions: PaletteOptions, garmentOptions: GarmentOptions,
                                matchOptions: MatchOptions, topK: Int, mask: UnsafeBufferPointer<UInt8>?,
                                regions: UnsafeBufferPointer<UInt8>?, regionCount: Int,
                                body: (OpaquePointer, GarmentAnalysisResult, ce_result) throws -> T) throws -> T {
    guard topK >= 1, topK <= Int(CE_MATCH_MAX_HITS), regionCount >= Int(Int32.min), regionCount <= Int(Int32.max) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let base = try validateRGBA(rgba, width: width, height: height, stride: stride)
    let maskBase = try validateMask(mask, width: width, height: height)
    let regionsBase = try validateRegions(regions, width: width, height: height)
    return try withEngineContext { ctx in
        var img = ce_image(pixels: base, width: Int32(width), height: Int32(height),
                           stride_bytes: Int32(stride), fmt: CE_RGBA8, mask: maskBase)
        var po = paletteOptions.cValue
        var go = garmentOptions.cValue
        var mo = matchOptions.cValue
        var res = ce_result()
        var out = [ce_garment_swatch](repeating: ce_garment_swatch(), count: Int(CE_PALETTE_MAX_COLORS))
        let rc = out.withUnsafeMutableBufferPointer { buf -> Int32 in
            ce_analyze_garments(ctx, &img, regionsBase, Int32(regionCount), &po, &go, &mo, &res, buf.baseAddress,
                                Int32(buf.count))
        }
        if rc < 0 {
            throw ColorEngineError.engine(code: rc)
        }
        let full = res
        let garments = out.prefix(Int(res.n_swatches)).map(GarmentSwatch.init)
        let analysis = analysisResult(from: &res, topK: topK)
        return try body(ctx, GarmentAnalysisResult(analysis: analysis, garments: garments), full)
    }
}

/// Regiones de prenda de una persona (`ce_mask_garment_regions`): para cada píxel de
/// `personMask` (> 0) dentro de la región de ropa de la pose, 1 (arriba: torso y brazos
/// superiores) o 2 (abajo: caderas a tobillos); 0 fuera. Los píxeles > 0 son
/// exactamente los que conserva `clothingRegions` con la misma máscara. Devuelve el mapa
/// (width * height bytes) y los píxeles etiquetados. Errores como `clothingRegions`.
public func garmentRegions(pose: Pose, options: RegionOptions = .default, personMask: [UInt8], width: Int,
                           height: Int) throws -> (regions: [UInt8], pixels: Int) {
    guard pose.joints.count == Int(CE_JOINT_COUNT.rawValue), maskDimsFit(width: width, height: height) else {
        throw ColorEngineError.engine(code: CE_ERR_ARG.rawValue)
    }
    let count = width * height
    guard personMask.count >= count else {
        throw ColorEngineError.maskTooSmall(required: count, actual: personMask.count)
    }
    var cPose = ce_pose()
    withUnsafeMutableBytes(of: &cPose.k) { raw in
        let kp = raw.bindMemory(to: ce_keypoint.self)
        for (i, j) in pose.joints.enumerated() {
            kp[i] = ce_keypoint(x: j.x, y: j.y, confidence: j.confidence)
        }
    }
    var opts = options.cValue
    var out = [UInt8](repeating: 0, count: count)
    let rc = personMask.withUnsafeBufferPointer { src in
        out.withUnsafeMutableBufferPointer { dst in
            ce_mask_garment_regions(&cPose, &opts, src.baseAddress, Int32(width), Int32(height), dst.baseAddress)
        }
    }
    if rc < 0 {
        throw ColorEngineError.engine(code: rc)
    }
    return (out, Int(rc))
}
