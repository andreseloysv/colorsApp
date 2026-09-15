// Tests XCTest del wrapper Swift: tres pares de Sharma (tolerancia 1e-4),
// blanco -> L = 100, y un round-trip básico. La batería completa (34 pares,
// golden files, round-trip exhaustivo) vive en engine/tests/test_math.c.
import XCTest
@testable import ColorEngine

final class ColorEngineTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(colorEngineVersion, "0.1.0")
    }

    func testSharmaPairs() {
        // Pares 1, 7 y 17 de Sharma, Wu y Dalal (2005).
        let cases: [(Lab, Lab, Double)] = [
            (Lab(L: 50.0000, a: 2.6772, b: -79.7751), Lab(L: 50.0000, a: 0.0000, b: -82.7485), 2.0425),
            (Lab(L: 50.0000, a: 0.0000, b: 0.0000), Lab(L: 50.0000, a: -1.0000, b: 2.0000), 2.3669),
            (Lab(L: 50.0000, a: 2.5000, b: 0.0000), Lab(L: 50.0000, a: 3.1736, b: 0.5854), 1.0000),
        ]
        for (x, y, expected) in cases {
            XCTAssertEqual(deltaE2000(x, y), expected, accuracy: 1e-4)
            XCTAssertEqual(deltaE2000(y, x), expected, accuracy: 1e-4)
        }
    }

    func testWhiteIsL100() {
        let w = srgbToLab(r: 255, g: 255, b: 255)
        XCTAssertEqual(w.L, 100.0, accuracy: 1e-9)
        XCTAssertEqual(w.a, 0.0, accuracy: 1e-9)
        XCTAssertEqual(w.b, 0.0, accuracy: 1e-9)
    }

    func testBlackIsZero() {
        let k = srgbToLab(r: 0, g: 0, b: 0)
        XCTAssertEqual(k.L, 0.0, accuracy: 1e-12)
        XCTAssertEqual(k.a, 0.0, accuracy: 1e-12)
        XCTAssertEqual(k.b, 0.0, accuracy: 1e-12)
    }

    func testRoundTrip() {
        let samples: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (255, 255, 255), (255, 0, 0), (12, 200, 77), (128, 128, 128)]
        for (r, g, b) in samples {
            let back = labToSrgb8(srgbToLab(r: r, g: g, b: b))
            XCTAssertEqual(back.r, r)
            XCTAssertEqual(back.g, g)
            XCTAssertEqual(back.b, b)
        }
    }

    func testDeltaEProperties() {
        let x = Lab(L: 41.5, a: 52.6, b: 26.9)
        let y = Lab(L: 60.0, a: -10.0, b: 5.0)
        XCTAssertEqual(deltaE2000(x, x), 0.0)
        XCTAssertEqual(deltaE2000(x, y), deltaE2000(y, x))
        XCTAssertGreaterThan(deltaE76(x, y), 0.0)
        XCTAssertLessThanOrEqual(deltaE2000(x, y, kL: 2, kC: 1, kH: 1), deltaE2000(x, y))
    }
}

// MARK: - Capa 2 (paleta)

final class PaletteTests: XCTestCase {
    /// Imagen RGBA sintética de tres bandas horizontales 50/30/20 con relleno
    /// de stride y alpha basura (deben ignorarse).
    private func threeBlockImage(width: Int, height: Int, stride: Int) -> [UInt8] {
        let colors: [(UInt8, UInt8, UInt8)] = [(200, 30, 40), (30, 60, 200), (40, 180, 60)]
        var px = [UInt8](repeating: 0x5A, count: stride * height)
        for y in 0..<height {
            let block = y < height / 2 ? 0 : (y < (height * 8) / 10 ? 1 : 2)
            for x in 0..<width {
                let o = y * stride + x * 4
                px[o] = colors[block].0
                px[o + 1] = colors[block].1
                px[o + 2] = colors[block].2
                px[o + 3] = UInt8((x * 7 + y) & 0xFF)
            }
        }
        return px
    }

    func testContextSizeBudget() {
        XCTAssertLessThanOrEqual(colorEngineContextSize, 2 * 1024 * 1024)
        XCTAssertEqual(colorEngineContextSize % 16, 0)
    }

    func testDefaultOptions() {
        let o = PaletteOptions.default
        XCTAssertEqual(o.kInit, 6)
        XCTAssertEqual(o.maxIters, 20)
        XCTAssertEqual(o.maxColors, 5)
        XCTAssertEqual(o.maxSide, 256)
        XCTAssertEqual(o.centerSigma, 0.35)
        XCTAssertEqual(o.mergeDeltaE, 5.0)
        XCTAssertEqual(o.minWeight, 0.05)
        XCTAssertFalse(o.skinRule)
    }

    func testThreeBlocksUniform() throws {
        let width = 120, height = 120, stride = width * 4 + 8
        let px = threeBlockImage(width: width, height: height, stride: stride)
        var opts = PaletteOptions.default
        opts.centerSigma = 0 // uniforme: pesos = fracción de área
        let palette = try px.withUnsafeBufferPointer { buf in
            try extractPalette(rgba: buf, width: width, height: height, stride: stride, options: opts)
        }
        XCTAssertEqual(palette.count, 3)
        let expected: [(Lab, Double)] = [
            (srgbToLab(r: 200, g: 30, b: 40), 0.5),
            (srgbToLab(r: 30, g: 60, b: 200), 0.3),
            (srgbToLab(r: 40, g: 180, b: 60), 0.2),
        ]
        for (sw, (lab, weight)) in zip(palette, expected) {
            XCTAssertLessThan(deltaE2000(sw.lab, lab), 1.0)
            XCTAssertEqual(sw.weight, weight, accuracy: 0.02)
        }
        XCTAssertEqual(palette.map(\.weight).reduce(0, +), 1.0, accuracy: 1e-12)
        XCTAssertEqual(palette[0].hex, "#c81e28")
        XCTAssertEqual(palette[1].r, 30)
        // Con peso al centro el conjunto de colores se mantiene (ΔE00 < 1).
        let centered = try px.withUnsafeBufferPointer { buf in
            try extractPalette(rgba: buf, width: width, height: height, stride: stride)
        }
        XCTAssertEqual(centered.count, 3)
        for (lab, _) in expected {
            XCTAssertLessThan(centered.map { deltaE2000($0.lab, lab) }.min()!, 1.0)
        }
    }

    func testErrors() throws {
        let px = [UInt8](repeating: 0, count: 16)
        try px.withUnsafeBufferPointer { buf in
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 4, height: 4, stride: 16)) { error in
                XCTAssertEqual(error as? ColorEngineError, .bufferTooSmall(required: 64, actual: 16))
            }
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 0, height: 1, stride: 4))
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 2, height: 2, stride: 4))
            // stride fuera del rango de Int32: error, nunca trap (el buffer de 16 bytes pasa el
            // check de tamaño porque height == 1).
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 1, height: 1, stride: Int(Int32.max) + 1)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -4)) // CE_ERR_STRIDE
            }
            var opts = PaletteOptions.default
            opts.kInit = 0
            XCTAssertThrowsError(try extractPalette(rgba: buf, width: 2, height: 2, stride: 8, options: opts)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
            }
        }
    }

    func testNearestDictionaryColor() {
        let lab = srgbToLab(r: 249, g: 193, b: 206) // color 0, Hermosa Pink
        let (index, de) = nearestDictionaryColor(lab)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(de, 0.0)
    }
}

// MARK: - Capa 3 (match)

final class MatchTests: XCTestCase {
    /// Imagen RGBA 120x120 (stride con relleno y alpha basura) de bandas
    /// verticales con proporciones iguales de los colores sRGB8 exactos de la
    /// combinación `id`.
    private func comboImage(id: Int, width: Int, height: Int, stride: Int) -> [UInt8]? {
        guard let colors = dictionaryCombo(id: id) else { return nil }
        let rgb = colors.compactMap { dictionaryColorRGB(index: $0) }
        guard rgb.count == colors.count else { return nil }
        var px = [UInt8](repeating: 0x5A, count: stride * height)
        for y in 0..<height {
            for x in 0..<width {
                let band = (x * rgb.count) / width
                let o = y * stride + x * 4
                px[o] = rgb[band].r
                px[o + 1] = rgb[band].g
                px[o + 2] = rgb[band].b
                px[o + 3] = UInt8((x * 7 + y) & 0xFF)
            }
        }
        return px
    }

    func testDefaultMatchOptions() {
        let m = MatchOptions.default
        XCTAssertEqual(m.kL, 1.0)
        XCTAssertEqual(m.kC, 1.0)
        XCTAssertEqual(m.kH, 1.0)
        XCTAssertEqual(m.coverageLambda, 1.0)
        XCTAssertEqual(m.ambiguousGap, 1.0)
        XCTAssertEqual(m.exposureEVMax, 1.0)
        XCTAssertEqual(m.exposurePenalty, 2.0)
        XCTAssertTrue(m.illuminantSearch)
        XCTAssertEqual(m.illuminantPenalty, 2.0)
        // Ida y vuelta por el struct C.
        var v0 = m
        v0.exposureEVMax = 0
        v0.illuminantSearch = false
        XCTAssertEqual(MatchOptions(v0.cValue), v0)
        XCTAssertEqual(colorEngineMaxHits, 10)
    }

    func testDictionaryAccessors() {
        XCTAssertEqual(dictionaryComboCount, 348)
        XCTAssertEqual(dictionaryColorCount, 159)
        XCTAssertEqual(dictionaryVersion.count, 12)
        XCTAssertNil(dictionaryCombo(id: 0))
        XCTAssertNil(dictionaryCombo(id: 349))
        XCTAssertNil(dictionaryColorRGB(index: -1))
        XCTAssertNil(dictionaryColorRGB(index: 159))
        XCTAssertNil(dictionaryColorLab(index: 159))
        XCTAssertNil(dictionaryColorName(index: 159))
        guard let combo = dictionaryCombo(id: 12) else { return XCTFail("combo 12") }
        XCTAssertTrue(combo.count >= 2 && combo.count <= 7)
        XCTAssertEqual(combo, combo.sorted())
        for index in combo {
            guard let rgb = dictionaryColorRGB(index: index), let lab = dictionaryColorLab(index: index) else {
                return XCTFail("color \(index)")
            }
            // Mismo Lab que la conversión de la foto (bit a bit).
            XCTAssertEqual(lab, srgbToLab(r: rgb.r, g: rgb.g, b: rgb.b))
            XCTAssertFalse((dictionaryColorName(index: index) ?? "").isEmpty)
        }
    }

    func testAnalyzeExactComboImage() throws {
        let id = 12
        let width = 120, height = 120, stride = width * 4 + 8
        guard let px = comboImage(id: id, width: width, height: height, stride: stride),
              let colors = dictionaryCombo(id: id) else { return XCTFail("fixture") }
        var po = PaletteOptions.default
        po.centerSigma = 0 // uniforme: pesos = fracción de área exacta
        let r = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po, topK: 3)
        }
        XCTAssertEqual(r.swatches.count, colors.count)
        XCTAssertEqual(r.swatches.map(\.weight).reduce(0, +), 1.0, accuracy: 1e-12)
        XCTAssertEqual(r.hits.count, 3)
        XCTAssertEqual(r.hits[0].comboId, id)
        XCTAssertLessThan(r.hits[0].score, 1e-9) // exacto salvo el redondeo de la media de Lloyd
        XCTAssertLessThan(r.hits[0].score, r.hits[1].score)
        XCTAssertLessThanOrEqual(r.hits[1].score, r.hits[2].score)
        XCTAssertFalse(r.ambiguous)
        // Cada swatch es un color de la combinación (ΔE00 ~ 0).
        for sw in r.swatches {
            let best = colors.compactMap { dictionaryColorLab(index: $0) }.map { deltaE2000($0, sw.lab) }.min()!
            XCTAssertLessThan(best, 1e-9)
        }
        // Determinismo run-a-run: resultado y hash idénticos.
        let r2 = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po, topK: 3)
        }
        XCTAssertEqual(r, r2)
        XCTAssertEqual(r.hash, r2.hash)
        // topK 10: prefijo idéntico, otro hash (cubre los K hits devueltos).
        let r10 = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po, topK: 10)
        }
        XCTAssertEqual(r10.hits.count, 10)
        XCTAssertEqual(Array(r10.hits.prefix(3)), r.hits)
        XCTAssertNotEqual(r10.hash, r.hash)
        // Con peso al centro (defecto) el top-1 se mantiene.
        let centered = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride)
        }
        XCTAssertEqual(centered.hits[0].comboId, id)
        // kL = 2 (textiles) y λ = 0 también aciertan sobre bloques exactos.
        let textiles = MatchOptions(kL: 2, kC: 1, kH: 1, coverageLambda: 0, ambiguousGap: 1)
        let rt = try px.withUnsafeBufferPointer { buf in
            try analyze(rgba: buf, width: width, height: height, stride: stride, paletteOptions: po,
                        matchOptions: textiles, topK: 1)
        }
        XCTAssertEqual(rt.hits.count, 1)
        XCTAssertEqual(rt.hits[0].comboId, id)
        XCTAssertFalse(rt.ambiguous)
    }

    func testAnalyzeErrors() throws {
        let px = [UInt8](repeating: 0, count: 64)
        try px.withUnsafeBufferPointer { buf in
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, topK: 0)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -1)) // CE_ERR_ARG
            }
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, topK: 11)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -1))
            }
            XCTAssertThrowsError(try analyze(rgba: buf, width: 8, height: 8, stride: 32)) { error in
                XCTAssertEqual(error as? ColorEngineError, .bufferTooSmall(required: 256, actual: 64))
            }
            XCTAssertThrowsError(try analyze(rgba: buf, width: 0, height: 4, stride: 16))
            var mo = MatchOptions.default
            mo.coverageLambda = -1
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, matchOptions: mo)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6)) // CE_ERR_OPTS
            }
            mo = MatchOptions.default
            mo.kL = .nan
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, matchOptions: mo)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
            }
            var po = PaletteOptions.default
            po.maxColors = 9
            XCTAssertThrowsError(try analyze(rgba: buf, width: 4, height: 4, stride: 16, paletteOptions: po)) { error in
                XCTAssertEqual(error as? ColorEngineError, .engine(code: -6))
            }
            // Caso válido mínimo: imagen negra 4x4 -> 1 swatch, 3 hits ordenados.
            let r = try analyze(rgba: buf, width: 4, height: 4, stride: 16)
            XCTAssertEqual(r.swatches.count, 1)
            XCTAssertEqual(r.hits.count, 3)
            XCTAssertLessThanOrEqual(r.hits[0].score, r.hits[1].score)
        }
    }
}
