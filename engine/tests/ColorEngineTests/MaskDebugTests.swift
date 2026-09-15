// Tests XCTest del wrapper Swift de máscaras (regiones de ropa, recorte de
// cabeza, piel adaptativa) y de las capas de depuración. La batería completa
// (rasterizador de referencia, invariancias, fuzz, paridad WASM) vive en
// engine/tests/test_mask.c y test_debug.c; aquí se comprueba que el puente
// Swift pasa los datos sin perder bits y que los errores llegan como
// ColorEngineError.
import XCTest
@testable import ColorEngine

/// Pose de frente de test_mask.c (200x400, coordenadas múltiplos de 1/4).
private func frontPose() -> Pose {
    var p = Pose()
    let pts: [(Joint, Double, Double, Double)] = [
        (.nose, 100, 50, 0.9), (.neck, 100, 90, 0.9), (.leftShoulder, 140, 90, 0.9), (.rightShoulder, 60, 90, 0.9),
        (.leftElbow, 152.25, 150.5, 0.8), (.rightElbow, 47.75, 150.5, 0.8), (.leftWrist, 158.5, 205.25, 0.7),
        (.rightWrist, 41.5, 205.25, 0.7), (.leftHip, 124, 210, 0.9), (.rightHip, 76, 210, 0.9),
        (.leftKnee, 126.25, 290.75, 0.8), (.rightKnee, 73.75, 290.75, 0.8), (.leftAnkle, 128.5, 370.5, 0.8),
        (.rightAnkle, 71.5, 370.5, 0.8), (.root, 100, 210, 0.9),
    ]
    for (j, x, y, c) in pts {
        p[j] = Keypoint(x: x, y: y, confidence: c)
    }
    return p
}

final class ClothingRegionTests: XCTestCase {
    func testDefaults() {
        let o = RegionOptions.default
        XCTAssertEqual(o.minConfidence, 0.3)
        XCTAssertEqual(o.torsoMargin, 0.12)
        XCTAssertEqual(o.limbWidth, 0.45)
        XCTAssertTrue(o.includeUpperArms)
        XCTAssertFalse(o.includeForearms)
        XCTAssertTrue(o.includeLegs)
        XCTAssertTrue(o.includeLowerLegs)
        XCTAssertEqual(RegionOptions(o.cValue), o)
        XCTAssertEqual(Pose().joints.count, 15)
        XCTAssertEqual(Joint.root.rawValue, 14)
        let s = SkinOptions.default
        XCTAssertEqual(s.maxMahalanobis, 2.5)
        XCTAssertEqual(s.maxExcludedFraction, 0.35)
    }

    func testFrontPoseMatchesCGolden() throws {
        let w = 200, h = 400
        let full = [UInt8](repeating: 255, count: w * h)
        let r = try clothingRegions(pose: frontPose(), mask: full, width: w, height: h)
        // Mismo recuento dorado que test_mask.c (rasterizador de referencia independiente).
        XCTAssertEqual(r.pixels, 26012)
        XCTAssertEqual(r.mask.count, w * h)
        XCTAssertEqual(r.mask.filter { $0 != 0 }.count, 26012)
        for y in 0..<90 {
            for x in 0..<w {
                XCTAssertEqual(r.mask[y * w + x], 0)
            }
        }
        XCTAssertEqual(r.mask[150 * w + 100], 255)
        var forearms = RegionOptions.default
        forearms.includeForearms = true
        XCTAssertEqual(try clothingRegions(pose: frontPose(), options: forearms, mask: full, width: w, height: h).pixels, 28090)
    }

    func testSymmetryAndErrors() throws {
        let w = 200, h = 400
        let full = [UInt8](repeating: 255, count: w * h)
        let reference = try clothingRegions(pose: frontPose(), mask: full, width: w, height: h)
        var oneHip = frontPose()
        oneHip[.rightHip] = .missing
        let estimated = try clothingRegions(pose: oneHip, mask: full, width: w, height: h)
        XCTAssertEqual(estimated.mask, reference.mask)
        var noHips = oneHip
        noHips[.leftHip] = .missing
        XCTAssertThrowsError(try clothingRegions(pose: noHips, mask: full, width: w, height: h)) { error in
            XCTAssertEqual(error as? ColorEngineError, .poseMissing)
        }
        XCTAssertEqual(ColorEngineError.poseMissing, .engine(code: -8))
        XCTAssertThrowsError(try clothingRegions(pose: Pose(joints: []), mask: full, width: w, height: h)) { error in
            XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
        }
        XCTAssertThrowsError(try clothingRegions(pose: frontPose(), mask: [UInt8](repeating: 1, count: 10), width: w, height: h)) { error in
            XCTAssertEqual(error as? ColorEngineError, .maskTooSmall(required: w * h, actual: 10))
        }
        var bad = RegionOptions.default
        bad.torsoMargin = .nan
        XCTAssertThrowsError(try clothingRegions(pose: frontPose(), options: bad, mask: full, width: w, height: h)) { error in
            XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
        }
        XCTAssertThrowsError(try clothingRegions(pose: frontPose(), mask: full, width: 0, height: h))
    }

    func testCutHead() {
        let w = 20, h = 40
        var m = [UInt8](repeating: 0, count: w * h)
        for y in 10..<30 { for x in 5..<15 { m[y * w + x] = 9 } }
        let r = cutHead(mask: m, width: w, height: h, fraction: 0.25)
        XCTAssertEqual(r.pixels, 15 * 10)
        XCTAssertEqual(r.mask[14 * w + 5], 0)
        XCTAssertEqual(r.mask[15 * w + 5], 9)
        XCTAssertEqual(cutHead(mask: m, width: w, height: h, fraction: 9).pixels, 10 * 10) // acotada a 0,5
        XCTAssertEqual(cutHead(mask: m, width: w, height: h, fraction: .nan).pixels, 20 * 10)
        let bad = cutHead(mask: [1, 2, 3], width: w, height: h, fraction: 0.2)
        XCTAssertEqual(bad.pixels, -1)
        XCTAssertEqual(bad.mask, [1, 2, 3])
        XCTAssertEqual(cutHead(mask: [UInt8](repeating: 0, count: w * h), width: w, height: h, fraction: 0.2).pixels, 0)
    }
}

final class SkinTests: XCTestCase {
    /// RGBA 200x400 (stride con relleno): cara y brazos de piel media con ruido
    /// ±4, torso rojo / azul marino; `skinTorso` pinta el torso del color de la piel.
    private func scene(skinTorso: Bool = false) -> (px: [UInt8], stride: Int) {
        let w = 200, h = 400, stride = w * 4 + 8
        var px = [UInt8](repeating: 0x33, count: stride * h)
        var state: UInt64 = 7
        func noise() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % 9) - 4
        }
        func paint(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: (Int, Int, Int)) {
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let o = y * stride + x * 4
                    px[o] = UInt8(clamping: c.0 + noise())
                    px[o + 1] = UInt8(clamping: c.1 + noise())
                    px[o + 2] = UInt8(clamping: c.2 + noise())
                }
            }
        }
        let skin = (198, 145, 110)
        paint(0, 0, w, h, (128, 128, 128))
        paint(70, 20, 130, 80, skin)
        paint(40, 100, 52, 300, skin)
        paint(148, 100, 160, 300, skin)
        paint(60, 100, 140, 200, skinTorso ? skin : (190, 30, 40))
        paint(60, 200, 140, 300, skinTorso ? skin : (30, 40, 90))
        return (px, stride)
    }

    private func rectMask(_ rects: [(Int, Int, Int, Int)]) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: 200 * 400)
        for (x0, y0, x1, y1) in rects {
            for y in y0..<y1 { for x in x0..<x1 { m[y * 200 + x] = 255 } }
        }
        return m
    }

    func testFitAndExclude() throws {
        let (px, stride) = scene()
        let face = rectMask([(70, 20, 130, 80)])
        let clothes = rectMask([(40, 100, 52, 300), (148, 100, 160, 300), (60, 100, 140, 300)])
        try px.withUnsafeBufferPointer { buf in
            let model = try fitSkinModel(rgba: buf, width: 200, height: 400, stride: stride, sampleMask: face)
            XCTAssertEqual(model.sampleCount, 3600)
            XCTAssertEqual(model.covariance.count, 9)
            XCTAssertLessThan(deltaE2000(model.mean, srgbToLab(r: 198, g: 145, b: 110)), 1.0)
            // Ida y vuelta por el struct C sin perder bits.
            XCTAssertEqual(SkinModel(model.cValue!), model)
            let r = try excludeSkin(rgba: buf, width: 200, height: 400, stride: stride, model: model, mask: clothes)
            XCTAssertFalse(r.guardTriggered)
            XCTAssertEqual(r.excluded, 4800) // los dos brazos enteros
            XCTAssertEqual(r.mask.filter { $0 != 0 }.count, 16000) // el torso rojo y azul intacto
        }
        // Prenda del color de la piel: salta la salvaguarda y la máscara sale intacta.
        let (skinPx, _) = scene(skinTorso: true)
        try skinPx.withUnsafeBufferPointer { buf in
            let model = try fitSkinModel(rgba: buf, width: 200, height: 400, stride: stride, sampleMask: face)
            let r = try excludeSkin(rgba: buf, width: 200, height: 400, stride: stride, model: model, mask: clothes)
            XCTAssertTrue(r.guardTriggered)
            XCTAssertEqual(r.excluded, 0)
            XCTAssertEqual(r.mask, clothes)
        }
    }

    func testSkinErrors() throws {
        let (px, stride) = scene()
        try px.withUnsafeBufferPointer { buf in
            let few = rectMask([(70, 20, 77, 27)]) // 49 muestras
            XCTAssertThrowsError(try fitSkinModel(rgba: buf, width: 200, height: 400, stride: stride, sampleMask: few)) { error in
                XCTAssertEqual(error as? ColorEngineError, .tooFewSkinSamples)
            }
            XCTAssertEqual(ColorEngineError.tooFewSkinSamples, .engine(code: -9))
            XCTAssertThrowsError(try fitSkinModel(rgba: buf, width: 200, height: 400, stride: stride, sampleMask: [1])) { error in
                XCTAssertEqual(error as? ColorEngineError, .maskTooSmall(required: 80000, actual: 1))
            }
            let model = try fitSkinModel(rgba: buf, width: 200, height: 400, stride: stride,
                                         sampleMask: rectMask([(70, 20, 130, 80)]))
            var degenerate = model
            degenerate.inverseCovariance = [Double](repeating: 0, count: 9)
            let m = rectMask([(60, 100, 140, 300)])
            XCTAssertThrowsError(try excludeSkin(rgba: buf, width: 200, height: 400, stride: stride, model: degenerate, mask: m)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
            }
            degenerate = model
            degenerate.covariance = []
            XCTAssertThrowsError(try excludeSkin(rgba: buf, width: 200, height: 400, stride: stride, model: degenerate, mask: m))
            degenerate = model
            degenerate.sampleCount = 3
            XCTAssertThrowsError(try excludeSkin(rgba: buf, width: 200, height: 400, stride: stride, model: degenerate, mask: m)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -9))
            }
            var opts = SkinOptions.default
            opts.maxExcludedFraction = 2
            XCTAssertThrowsError(try excludeSkin(rgba: buf, width: 200, height: 400, stride: stride, model: model, options: opts, mask: m))
        }
    }
}

final class DebugLayerTests: XCTestCase {
    /// Composición de test_debug.c en RGBA: rojo, azul, verde y amarillo por
    /// cuadrantes, magenta 6x6 dentro del rojo; máscara que anula el amarillo.
    private func scene() -> (px: [UInt8], mask: [UInt8]) {
        let w = 200, h = 200
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var mask = [UInt8](repeating: 255, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var c: (UInt8, UInt8, UInt8) = y < 100 ? (x < 100 ? (200, 30, 40) : (30, 60, 200))
                                                       : (x < 100 ? (40, 180, 60) : (230, 210, 40))
                if y >= 40, y < 46, x >= 40, x < 46 { c = (200, 30, 200) }
                let o = (y * w + x) * 4
                px[o] = c.0
                px[o + 1] = c.1
                px[o + 2] = c.2
                px[o + 3] = 255
                if y >= 100, x >= 100 { mask[y * w + x] = 0 }
            }
        }
        return (px, mask)
    }

    func testLayersFromOneAnalysis() throws {
        let (px, mask) = scene()
        var po = PaletteOptions.default
        po.centerSigma = 0
        let (layers, plain) = try px.withUnsafeBufferPointer { buf in
            try mask.withUnsafeBufferPointer { m in
                (try paletteDebugLayers(rgba: buf, width: 200, height: 200, stride: 800, paletteOptions: po, topK: 3, mask: m),
                 try analyze(rgba: buf, width: 200, height: 200, stride: 800, paletteOptions: po, topK: 3, mask: m))
            }
        }
        // El análisis es el mismo que el de analyze (hash incluido).
        XCTAssertEqual(layers.analysis, plain)
        let d = layers.debug
        XCTAssertEqual(d.reducedWidth, 200)
        XCTAssertEqual(d.reducedHeight, 200)
        XCTAssertEqual(d.swatchCount, 3)
        XCTAssertEqual(d.zeroWeightFraction, 0.25)
        XCTAssertEqual(d.centerSigmaPx, 0)
        XCTAssertEqual(d.clusters.count, 4)
        XCTAssertEqual(d.clusters.filter { $0.fate == .kept }.count, 3)
        let magenta = d.clusters.first { $0.fate == .discarded }
        XCTAssertNotNil(magenta)
        XCTAssertNil(magenta?.finalIndex)
        XCTAssertEqual(magenta?.hex, "#c81ec8")
        XCTAssertEqual(layers.reducedRGB.count, 200 * 200 * 3)
        XCTAssertEqual(Array(layers.reducedRGB.prefix(3)), [200, 30, 40])
        XCTAssertEqual(layers.labelMap[150 * 200 + 150], paletteLabelNone)
        XCTAssertEqual(layers.clusterMap[150 * 200 + 150], paletteLabelNone)
        XCTAssertEqual(layers.weightMap[150 * 200 + 150], 0)
        XCTAssertEqual(layers.labelMap[42 * 200 + 42], paletteLabelDiscarded)
        let red = layers.labelMap[10 * 200 + 10]
        XCTAssertLessThan(Int(red), 3)
        XCTAssertLessThan(deltaE2000(layers.analysis.swatches[Int(red)].lab, srgbToLab(r: 200, g: 30, b: 40)), 1e-9)
        XCTAssertEqual(layers.weightMap[10 * 200 + 10], 255)
        // Cada hit explicado con su score bit a bit y la suma de términos.
        XCTAssertEqual(layers.explanations.count, 3)
        for (hit, e) in zip(layers.analysis.hits, layers.explanations) {
            XCTAssertEqual(e.comboId, hit.comboId)
            XCTAssertEqual(e.score.bitPattern, hit.score.bitPattern)
            XCTAssertEqual((e.fitTerm + e.coverageTerm + e.hypothesisPenalty).bitPattern, e.score.bitPattern)
            XCTAssertEqual(e.perSwatch.count, 3)
            XCTAssertEqual(e.perColor.count, dictionaryCombo(id: e.comboId)?.count)
            XCTAssertEqual(e.perColor.map(\.colorIndex), dictionaryCombo(id: e.comboId))
            // explainMatch independiente (otro contexto) da lo mismo.
            let again = try explainMatch(swatches: layers.analysis.swatches, comboId: hit.comboId)
            XCTAssertEqual(again, e)
        }
    }

    func testExplainErrors() throws {
        let sw = [Swatch(lab: srgbToLab(r: 200, g: 30, b: 40), r: 200, g: 30, b: 40, weight: 1)]
        XCTAssertThrowsError(try explainMatch(swatches: [], comboId: 1)) { error in
            XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
        }
        XCTAssertThrowsError(try explainMatch(swatches: sw, comboId: 349)) { error in
            XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
        }
        var mo = MatchOptions.default
        mo.coverageLambda = -1
        XCTAssertThrowsError(try explainMatch(swatches: sw, options: mo, comboId: 1)) { error in
            XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
        }
        let e = try explainMatch(swatches: sw, options: MatchOptions(kL: 1, kC: 1, kH: 1, coverageLambda: 1, ambiguousGap: 1,
                                                                   exposureEVMax: 0, exposurePenalty: 2,
                                                                   illuminantSearch: false, illuminantPenalty: 2),
                                 comboId: 1)
        XCTAssertEqual(e.illuminant, -1)
        XCTAssertEqual(e.exposureEV, 0)
        XCTAssertEqual(e.hypothesisPenalty, 0)
        let px = [UInt8](repeating: 0, count: 16)
        try px.withUnsafeBufferPointer { buf in
            XCTAssertThrowsError(try paletteDebugLayers(rgba: buf, width: 2, height: 2, stride: 8, topK: 0))
            XCTAssertThrowsError(try paletteDebugLayers(rgba: buf, width: 4, height: 4, stride: 16)) { error in
                XCTAssertEqual(error as? ColorEngineError, .bufferTooSmall(required: 64, actual: 16))
            }
        }
    }
}
